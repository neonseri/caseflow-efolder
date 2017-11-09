class Fetcher
  include ActiveModel::Model
  attr_accessor :document, :external_service

  def content(save_document_metadata: true)
    if save_document_metadata
      download_from_service_and_record
    else
      download_from_service
    end
  end

  private

  def cached_content
    @cached_content ||= S3Service.fetch_content(document.s3_filename)
  end

  def convert_from_tiff(result)
    MetricsService.record("Image Magick: Convert tiff to pdf",
                          service: :image_magick,
                          name: "convert") do
      base_path = File.join(Rails.application.config.download_filepath, "tiff_convert")
      FileUtils.mkdir_p(base_path) unless File.exist?(base_path)

      tiff_name = File.join(base_path, document.s3_filename)

      File.open(tiff_name, "wb") do |f|
        f.write(result)
      end

      document.update_attributes!(converted_mime_type: "application/pdf")
      pdf_name = File.join(base_path, document.s3_filename)

      MiniMagick::Tool::Convert.new do |convert|
        convert << tiff_name
        convert << pdf_name
      end

      File.open(pdf_name, "r", &:read)
    end
  end

  # Adding a magic number check based on this recommendation: https://imagetragick.com/
  def tiff?(data)
    "MM\u0000*" == data[0..3] || "II*\u0000" == data[0..3]
  end

  def download_from_service
    return cached_content if cached_content

    result = external_service.fetch_document_file(document)
    result = convert_from_tiff(result) if document.mime_type == "image/tiff" && tiff?(result)
    S3Service.store_file(document.s3_filename, result)
  end

  def download_from_service_and_record
    document.update_attributes!(started_at: Time.zone.now)
    download_from_service.tap do |result|
      document.update_attributes!(
        completed_at: Time.zone.now,
        download_status: :success,
        size: result.try(:bytesize)
      )
    end
  end
end

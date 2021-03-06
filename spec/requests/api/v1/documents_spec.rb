describe "Documents API v1", type: :request do
  context "Document by document ID" do
    let!(:current_user) do
      User.authenticate!(roles: ["Reader"])
    end

    let(:download) do
      Download.create(
        file_number: "21012",
        veteran_first_name: "George",
        veteran_last_name: "Washington",
        user: current_user
      )
    end
    let(:document) do
      download.documents.create(
        id: 34,
        document_id: "{3333-3333}",
        received_at: Time.utc(2015, 9, 6, 1, 0, 0),
        type_id: "825",
        mime_type: "application/pdf"
      )
    end

    before do
      allow(S3Service).to receive(:fetch_content).and_return("hello there")
      FeatureToggle.enable!(:reader_api)
    end

    context "returns 401 if user does not have Reader role" do
      let!(:current_user) do
        User.authenticate!(roles: [""])
      end

      it do
        get "/api/v1/documents/8888"
        expect(response.code).to eq("401")
      end
    end

    it "returns 404 if document ID is not found" do
      get "/api/v1/documents/8888"
      expect(response.code).to eq("404")
    end

    it "returns a document" do
      get "/api/v1/documents/#{document.id}"
      expect(response.code).to eq("200")
      expect(response.body).to eq("hello there")
      expect(response.headers["Cache-Control"]).to match(/2592000/)
    end

    it "returns 502 if there is a VBMS error" do
      allow_any_instance_of(Fetcher).to receive(:content).and_raise(VBMS::ClientError)

      get "/api/v1/documents/#{document.id}"

      expect(response.code).to eq("502")

      json = JSON.parse(response.body)
      expect(json["errors"].length).to eq(1)
      expect(json["errors"].first["title"]).to eq("Document download failed")
      expect(json["errors"].first["detail"]).to eq("An upstream dependency failed to fetch document contents.")
    end

    it "returns 502 if there is a VVA error" do
      allow_any_instance_of(Fetcher).to receive(:content).and_raise(VVA::ClientError)

      get "/api/v1/documents/#{document.id}"

      expect(response.code).to eq("502")

      json = JSON.parse(response.body)
      expect(json["errors"].length).to eq(1)
      expect(json["errors"].first["title"]).to eq("Document download failed")
      expect(json["errors"].first["detail"]).to eq("An upstream dependency failed to fetch document contents.")
    end

    it "returns 500 if there is a Caseflow eFolder error" do
      allow_any_instance_of(Fetcher).to receive(:content).and_raise(ActiveRecord::StaleObjectError.new(nil, nil))

      get "/api/v1/documents/#{document.id}"

      expect(response.code).to eq("500")

      json = JSON.parse(response.body)
      expect(json["errors"].length).to eq(1)
      expect(json["errors"].first["title"]).to eq("Document download failed")
      expect(json["errors"].first["detail"]).to eq("Caseflow eFolder failed to fetch document contents.")
    end

    context "When user doesn't own corresponding download record" do
      let(:download) do
        Download.create(
          file_number: "21012",
          veteran_first_name: "George",
          veteran_last_name: "Washington",
          user: User.create(css_id: "1234", station_id: "567")
        )
      end

      it "returns 403" do
        get "/api/v1/documents/#{document.id}", nil, headers
        expect(response.code).to eq("403")
        body = JSON.parse(response.body)
        expect(body["status"]).to match(/sensitive/)
      end
    end

    it "returns 500 on any other error" do
      allow_any_instance_of(Fetcher).to receive(:content).and_raise("Much random error")
      expect(Raven).to receive(:capture_exception)
      expect(Raven).to receive(:last_event_id).and_return("a1b2c3")

      get "/api/v1/documents/#{document.id}"

      expect(response.code).to eq("500")

      json = JSON.parse(response.body)
      expect(json["errors"].length).to eq(1)
      expect(json["errors"].first["title"]).to eq("Unknown error occured")
      expect(json["errors"].first["detail"]).to match("Much random error (Sentry event id: a1b2c3)")
    end
  end
end

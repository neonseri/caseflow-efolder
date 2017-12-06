# frozen_string_literal: true
class User < ActiveRecord::Base
  has_many :searches
  has_many :downloads
  # v2 relationship
  has_many :user_manifests
  has_many :manifests, through: :user_manifests

  NO_EMAIL = "No Email Recorded".freeze

  attr_accessor :name, :roles, :ip_address

  def display_name
    return "Unknown" if name.nil?
    name
  end

  # We should not use user.can?("System Admin"), but user.admin? instead
  def can?(function)
    return true if admin?
    # Check if user is granted the function
    return true if granted?(function)
    # Check if user is denied the function
    return false if denied?(function)
    # Ignore "System Admin" function from CSUM/CSEM users
    return false if function.include?("System Admin")
    roles ? roles.include?(function) : false
  end

  def admin?
    Functions.granted?("System Admin", css_id)
  end

  def granted?(thing)
    Functions.granted?(thing, css_id)
  end

  def denied?(thing)
    Functions.denied?(thing, css_id)
  end

  class << self
    def from_session_and_request(session, request)
      return nil unless session["user"]
      visitor = AuthenticatedVisitor.new(session["user"])
      find_or_create_by(css_id: visitor.css_id, station_id: visitor.station_id).tap do |u|
        u.name = visitor.name
        u.email = visitor.email
        u.roles = visitor.roles
        u.ip_address = request.remote_ip
        u.save
      end
    end

    def from_api_authenticated_values(css_id:, station_id:)
      visitor = AuthenticatedVisitor.new(css_id: css_id, station_id: station_id)
      find_or_create_by(css_id: visitor.css_id, station_id: visitor.station_id)
    end
  end
end

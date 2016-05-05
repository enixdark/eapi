# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'
# use ActiveRecord::ConnectionAdapters::ConnectionManagement
run Rails.application
run V1::API

require 'sinatra/base'
require 'aws-sdk-s3'

require 'vagrancy/filestore'
require 'vagrancy/filestore_configuration'
require 'vagrancy/upload_path_handler'
require 'vagrancy/box'
require 'vagrancy/provider_box'
require 'vagrancy/dummy_artifact'
require 'vagrancy/dummy_version'
require 'vagrancy/dummy_provider'
require 'vagrancy/invalid_file_path'

module Vagrancy
  class App < Sinatra::Base
    set :logging, true
    set :show_exceptions, :after_handler

    error Vagrancy::InvalidFilePath do
      status 403
      env['sinatra.error'].message
    end

    # Vagrant Cloud emulation, no authentication
    get '/authenticate' do
      status 200
    end

    # Vagrant Cloud emulation, stepVerifyBox
    get '/box/:username/:name' do
      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)
      boxVersions = box.to_json
      logger.info boxVersions

      status 200
      content_type 'application/json'
      boxVersions
    end

    # Vagrant Cloud emulation, stepCreateVersion
    post '/box/:username/:name/versions' do
      status 200
      content_type 'application/json'
      DummyVersion.new(request.body.read).to_json
    end

    # Vagrant Cloud emulation, stepCreateProvider
    post '/box/:username/:name/version/:version/providers' do
      status 200
      content_type 'application/json'
      DummyProvider.new(request.body.read).to_json
    end

    # Vagrant Cloud emulation, stepPrepareUpload
    get '/box/:username/:name/version/:version/provider/:provider/upload' do

      upload_path = "#{request.scheme}://#{request.host}:#{request.port.to_s}/#{params[:username]}/#{params[:name]}/#{params[:version]}/#{params[:provider]}"

      logger.info "Upload..."

      if !ENV['S3_BUCKET_NAME'].to_s.empty? then
        if !ENV['AWS_ENDPOINT'].to_s.empty? then
          # Used for local development using Minio. If endpoint is overriden then we expect access key and secret key to be specified as well
          s3 = Aws::S3::Client.new(
            endpoint: ENV['AWS_ENDPOINT'],
            access_key_id: ENV['AWS_ACCESS_KEY_ID'],
            secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
            force_path_style: true
          )
        else
          s3 = Aws::S3::Client.new(
            use_accelerate_endpoint: true
          )
        end

        signer = Aws::S3::Presigner.new(client: s3)
        upload_path = signer.presigned_url(
          :put_object,
          bucket: ENV['S3_BUCKET_NAME'],
          key: "data/#{params[:username]}/#{params[:name]}/#{params[:version]}/#{params[:provider]}/box"
        )
      end

      status 200
      {
        :upload_path => upload_path
      }.to_json
    end

    # Vagrant Cloud emulation, clean provider
    delete '/box/:username/:name/version/:version/provider/:provider' do
      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)
      provider_box = ProviderBox.new(params[:provider], params[:version], box, filestore, request)

      status 200
      provider_box.delete
    end

    # Vagrant Cloud emulation, stepRelease
    put '/box/:username/:name/version/:version/release' do
      status 200
    end

    # Upload
    put '/:username/:name/:version/:provider' do
      logger.info "Upload box /#{params[:username]}/#{params[:name]}/#{params[:version]}/#{params[:provider]}"

      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)
      provider_box = ProviderBox.new(params[:provider], params[:version], box, filestore, request)

      provider_box.write(request.body, logger)
      status 200
      # status 201
    end

    # Vagrant
    get '/:username/:name' do
      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)

      status box.exists? ? 200 : 404
      content_type 'application/json'
      box.to_json if box.exists?
    end

    # Old
    get '/:username/:name/:version/:provider' do
      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)
      provider_box = ProviderBox.new(params[:provider], params[:version], box, filestore, request)

      if !ENV['S3_BUCKET_NAME'].to_s.empty? then
        if !ENV['AWS_ENDPOINT'].to_s.empty? then
          # Used for local development using Minio. If endpoint is overriden then we expect access key and secret key to be specified as well
          s3 = Aws::S3::Client.new(
            endpoint: ENV['AWS_ENDPOINT'],
            access_key_id: ENV['AWS_ACCESS_KEY_ID'],
            secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
            force_path_style: true
          )
        else
          s3 = Aws::S3::Client.new(
            use_accelerate_endpoint: true
          )
        end

        signer = Aws::S3::Presigner.new(client: s3)
        box_path = signer.presigned_url(
          :get_object,
          bucket: ENV['S3_BUCKET_NAME'],
          key: "data/#{params[:username]}/#{params[:name]}/#{params[:version]}/#{params[:provider]}/box"
        )

        redirect box_path
        return
      end
      
      send_file filestore.file_path(provider_box.file_path) if provider_box.exists?
      status provider_box.exists? ? 200 : 404
    end

    delete '/:username/:name/:version/:provider' do
      box = Vagrancy::Box.new(params[:name], params[:username], filestore, request)
      provider_box = ProviderBox.new(params[:provider], params[:version], box, filestore, request)

      status provider_box.exists? ? 200 : 404
      provider_box.delete
    end

    post '/api/v1/artifacts/:username/:name/vagrant.box' do
      content_type 'application/json'
      UploadPathHandler.new(params[:name], params[:username], request, filestore).to_json
    end

    get '/api/v1/artifacts/:username/:name' do
      status 200
      content_type 'application/json'
      DummyArtifact.new(params).to_json
    end

    def filestore
      config = FilestoreConfiguration.new
      Filestore.new(config.path, config.tmp)
    end

  end
end

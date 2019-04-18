require 'json'

module Vagrancy
  class DummyVersion

    def initialize(body)
      @version = JSON.parse body
    end

    def to_json
      { 
      	:version => @version['version']['version']
      }.to_json
    end

  end
end

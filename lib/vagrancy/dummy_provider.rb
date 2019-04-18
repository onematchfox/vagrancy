require 'json'

module Vagrancy
  class DummyProvider

    def initialize(body)
      @provider = JSON.parse body
    end

    def to_json
      { 
      	:name => @provider['provider']['name']
      }.to_json
    end

  end
end

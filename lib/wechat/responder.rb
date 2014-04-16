module Wechat
  module Responder
    extend ActiveSupport::Concern

    included do 
      self.skip_before_filter :verify_authenticity_token
      self.before_filter :verify_signature, only: [:show, :create]
      #delegate :wehcat, to: :class
    end

    module ClassMethods

      attr_accessor :wechat, :token

      def on message_type, respond: nil, &block
        raise "Unknow message type" unless message_type.in? [:text, :image, :voice, :video, :location, :link, :event, :fallback]
        config=respond.nil? ? {} : {:respond=>respond}
        config.merge!(:proc=>block) if block_given?

        responders(message_type) << config
        return config
      end

      def responders type
        @responders ||= Hash.new
        @responders[type] ||= Array.new
      end

      def responder_for message, &block
        message_type = message[:MsgType].to_sym
        responders = responders(message_type)
        yield(responders.first, message)        
      end

    end

    
    def show
      render :text => params[:echostr]
    end

    def create 
      p = Hash.from_xml request.body     
      request = Wechat::Message.from_hash(p["xml"].symbolize_keys)
      response = self.class.responder_for(request) do |responder, *args|
        responder ||= self.class.responders(:fallback).first

        next if responder.nil?
        next request.reply.text responder[:respond] if (responder[:respond])
        next responder[:proc].call(*args.unshift(request)) if (responder[:proc])
      end

      if response.respond_to? :to_xml
        render xml: response.to_xml
      else
        render :nothing => true, :status => 200, :content_type => 'text/html'
      end
    end

    private
    def verify_signature
      array = [self.class.token, params[:timestamp], params[:nonce]].compact.sort
      render :text => "Forbidden", :status => 403 if params[:signature] != Digest::SHA1.hexdigest(array.join)
    end
  end
end
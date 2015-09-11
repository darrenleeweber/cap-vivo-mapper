module Cap
  module Client

    require 'faraday'
    require 'faraday_middleware'

    # CAP Public Website  https://profiles.stanford.edu
    # Profiles API        https://api.stanford.edu/profiles/v1
    # Orgs API            https://api.stanford.edu/cap/v1/orgs
    # Search API          https://api.stanford.edu/cap/v1/search
    # Developer's API     https://cap.stanford.edu/cap-api/console

    class Client

      JSON_CONTENT = 'application/json'

      attr_reader :config
      attr_reader :cap_api
      attr_reader :profiles

      # Initialize a new client
      def initialize
        @config = Cap::Client.configuration
        if Cap.configuration.cap_repo.is_a? Daybreak::DB
          @profiles = Cap.configuration.cap_repo
        elsif Cap.configuration.cap_repo.is_a? Mongo::Client
          @profiles = Cap.configuration.cap_repo[:profiles]
          @presentations = Cap.configuration.cap_repo[:presentations]
          @publications = Cap.configuration.cap_repo[:publications]
          @processed = Cap.configuration.cap_repo[:processed]
        end
        # CAP API
        @cap_uri = 'https://api.stanford.edu'
        @cap_profiles = '/profiles/v1'
        @cap_orgs     = '/cap/v1/orgs'
        @cap_search   = '/cap/v1/search'
        @cap_api = Faraday.new(url: @cap_uri) do |f|
          # f.use FaradayMiddleware::FollowRedirects, limit: 3
          # f.use Faraday::Response::RaiseError # raise exceptions on 40x, 50x
          # f.request :logger, @config.logger
          f.request :json
          f.response :json, :content_type => JSON_CONTENT
          f.adapter Faraday.default_adapter
        end
        @cap_api.options.timeout = 90
        @cap_api.options.open_timeout = 10
        @cap_api.headers.merge!(json_payloads)
        # Authentication
        auth_uri = 'https://authz.stanford.edu/oauth/token'
        @auth = Faraday.new(url: auth_uri) do |f|
          f.request  :url_encoded
          f.response :json, :content_type => JSON_CONTENT
          f.adapter  Faraday.default_adapter
        end
        @auth.options.timeout = 30
        @auth.options.open_timeout = 10
        @auth.headers.merge!(json_payloads)
      end

      # Reset authentication
      def authenticate!
        @access_expiry = nil
        authenticate
      end

      def authenticate
        if @access_expiry.to_i < Time.now.to_i
          @access_code = nil
          @auth.headers.delete :Authorization
          @cap_api.headers.delete :Authorization
        end
        @access_code || begin
          return false if @config.token_user.empty? && @config.token_pass.empty?
          client = "#{@config.token_user}:#{@config.token_pass}"
          auth_code = 'Basic ' + Base64.strict_encode64(client)
          @auth.headers.merge!({ Authorization: auth_code })
          response = @auth.get "?grant_type=client_credentials"
          return false unless response.status == 200
          access = response.body
          return false if access['access_token'].nil?
          @access_code = "Bearer #{access['access_token']}"
          @access_expiry = Time.now.to_i + access['expires_in'].to_i
          @cap_api.headers[:Authorization] = @access_code
        end
      end

      # Get profiles from CAP API and store into local repo
      def get_profiles
        begin
          if authenticate
            page = 1
            pages = 0
            total = 0
            begin
              repo_clean
              while true
                params = "?p=#{page}&ps=100"
                response = @cap_api.get "#{@cap_profiles}#{params}"
                if response.status == 200
                  data = response.body
                  if data['firstPage']
                    pages = data['totalPages']
                    total = data['totalCount']
                    puts "Retrieved #{page} of #{pages} pages (#{total} profiles)."
                  else
                    puts "Retrieved #{page} of #{pages} pages."
                  end
                  profiles = data['values']
                  profiles.each {|profile| profile_insert(profile) }
                  @profiles.flush if @profiles.is_a? Daybreak::DB
                  page += 1
                  break if data['lastPage']
                else
                  msg = "Failed to GET profiles page #{page}: #{response.status}"
                  @config.logger.error msg
                  puts msg
                  break
                end
              end
            rescue => e
              msg = e.message
              binding.pry if @config.debug
              @config.logger.error msg
            ensure
              repo_commit(total)
            end
          else
            msg = "Failed to authenticate"
            @config.logger.error msg
          end
        rescue => e
          msg = e.message
          binding.pry if @config.debug
          @config.logger.error(msg)
        end
      end

      # TODO: provide a method for retrieving the CAP API data
      #       for profileId and lastModified and determine
      #       whether the local repo data should be updated.
      #
      # api/profiles/v1?ps=1&vw=brief
      #
      # def update_profiles
      #   # profile['profileId']
      #   # => 42005
      #   # [13] pry(main)> profile['profileId'].class
      #   # => Fixnum
      #   # [14] pry(main)> profile['lastModified']
      #   # => "2015-08-17T10:55:46.772-07:00"
      # end

      # @return ids [Array<Integer>] profile ids from local repo
      def profile_ids
        if @profiles.is_a? Daybreak::DB
          @profiles.keys.map {|k| k.to_i}
        elsif @profiles.is_a? Mongo::Collection
          @profiles.find.projection({_id:1}).map {|p| p['_id'] }
        end
      end

      # return profile data from local repo
      # @param id [Integer] A profileId number
      # @return profile [Hash|nil]
      def profile(id)
        if @profiles.is_a? Daybreak::DB
          @profiles[id.to_s]
        elsif @profiles.is_a? Mongo::Collection
          profile = @profiles.find({_id: id}).first
          profile['profileId'] = profile.delete('_id')
          profile
        end
      end

      # Remove privileged fields from profile data
      # @param profile [Hash] CAP profile data
      def profile_clean(profile)
        @@priv_fields ||= %w(uid universityId)
        if @config.clean
          @@priv_fields.each {|f| profile.delete(f)}
        end
      end

      # Insert profile data in local repo
      # @param profile [Hash] CAP profile data
      def profile_insert(profile)
        profile_clean(profile)
        if @profiles.is_a? Daybreak::DB
          id = profile["profileId"]
          @profiles[id] = profile
        elsif @profiles.is_a? Mongo::Collection
          # split out the publication data to accommodate size limit on mongo
          id = profile.delete('profileId')
          profile['_id'] = id  # use 'profileId' as the mongo _id
          presentations = profile.delete('presentations') || []
          presentations.each {|p| p.delete('detail')}
          pres = {'_id' => id, 'presentations' => presentations}
          begin
            @presentations.insert_one(pres)
          rescue
            msg = "Profile #{id} presentations failed to save."
            @config.logger.error msg
          end
          @pubs_fields ||= ['doiId', 'doiUrl', 'webOfScienceId', 'webOfScienceUrl']
          publications = profile.delete('publications') || []
          publications.each do |p|
            p.keys {|k| p.delete(k) unless @pubs_fields.include? k }
          end
          pub = {'_id' => id, 'publications' => publications}
          begin
            @publications.insert_one(pub)
          rescue
            msg = "Profile #{id} publications failed to save."
            @config.logger.error msg
          end
          begin
            @profiles.insert_one(profile)
          rescue
            msg = "Profile #{id} failed to save."
            @config.logger.error msg
          end
          begin
            cap_modified = profile['lastModified'] || 0
            cap_modified = Time.parse(cap_modified).to_i
            data = process_data(id)
            data['cap_modified'] = cap_modified
            data['cap_retrieved'] = Time.now.to_i
            process_update(id, data)
          rescue
            msg = "Profile #{id}: failed to update process data."
            @config.logger.error msg
          end
        end
      end

      # return presentation data from local repo
      # @param id [Integer] A profileId number
      # @return presentations [Array<Hash>|nil]
      def presentation(id)
        if @profiles.is_a? Daybreak::DB
          begin
            @profiles[id.to_s]['presentations']
          rescue
            nil
          end
        elsif @profiles.is_a? Mongo::Collection
          @presentations.find({_id: id}).first
        end
      end

      # return publication data from local repo
      # @param id [Integer] A profileId number
      def publication(id)
        if @profiles.is_a? Daybreak::DB
          begin
            @profiles[id.to_s]['publications']
          rescue
            nil
          end
        elsif @profiles.is_a? Mongo::Collection
          @publications.find({_id: id}).first
        end
      end

      # A profile's processing data.
      # @param id [Integer] A profileId number
      # @return data [Hash] Processing information
      def process_data(id)
        if @profiles.is_a? Daybreak::DB
          begin
            @profiles[id.to_s]['processed']
          rescue
            {}
          end
        elsif @processed.is_a? Mongo::Collection
          @processed.find({_id: id}).first || {}
        end
      end

      # Update a profile record with lastModified time and processing data.
      # @param id [Integer] A profileId number
      # @param data [Hash] Optional processing information
      def process_update(id, data=nil)
        if @profiles.is_a? Daybreak::DB
          process_doc = {
            lastModified: Time.now.to_i,
            data: data
          }
          @profiles[id.to_s]['processed'] = process_doc
        elsif @processed.is_a? Mongo::Collection
          process_doc = {
            _id: id,
            lastModified: Time.now.to_i,
            data: data
          }
          @processed.insert_one(process_doc)
        end
      end

      def repo_clean
        if @profiles.is_a? Daybreak::DB
          @profiles.clear
        elsif @profiles.is_a? Mongo::Collection
          @profiles.drop
          @profiles.create
          @presentations.drop
          @presentations.create
          @publications.drop
          @publications.create
          @processed.drop
          @processed.create
        end
      end

      private

      def repo_commit(total)
        if @profiles.is_a? Daybreak::DB
          @profiles.flush
          @profiles.compact
          @profiles.load
          puts "Stored #{@profiles.size} of #{total} profiles."
          puts "Stored profiles to #{@profiles.class} at: #{@profiles.file}."
        elsif @profiles.is_a? Mongo::Collection
          puts "Stored #{@profiles.find.count} of #{total} profiles."
          puts "Stored profiles to #{@profiles.class} at: #{@profiles.namespace}."
        end
      end

      # # Migrate CAP API profile data from a Daybreak::DB into mongodb
      # def profiles_daybreak_to_mongo
      #   mongo = Cap.configuration.cap_repo_mongo
      #   mongo[:profiles].drop
      #   db = Cap.configuration.cap_repo_daybreak
      #   db.keys do |id|
      #     profile = profiles[id]
      #     mongo[:profiles].insert_one(profile)
      #   end
      #   # mongo[:profiles].indexes.create_one({profileId:1}, :unique => true )
      #   daybreak_matches_mongo?
      # end

      # # Validate a daybreak to mongo data transfer
      # def daybreak_matches_mongo?
      #   mongo = Cap.configuration.cap_repo_mongo
      #   profiles = Cap.configuration.cap_repo_daybreak
      #   matches = profiles.keys.map do |id|
      #     profile = profiles[id]
      #     mongo_profile = mongo[:profiles].find({_id: id.to_i}).first
      #     id = mongo_profile.delete("_id")
      #     mongo_profile['profileId'] = id
      #     mongo_profile == profile
      #   end
      #   matches.all?  # should be true
      # end

      def json_payloads
        { accept: JSON_CONTENT, content_type: JSON_CONTENT }
      end

    end
  end
end

require "twitter-text"
class Tweet < CouchRest::Model::Base 

	include Twitter::Extractor
	use_database CouchRest.new("http://localhost:5984").database("tweets")

	@@properties = ["created_at", "entities", "id", "in_reply_to_screen_name", "text"]
	
	@@properties.each do |p|
		property p.to_sym
	end	

	view_by :hour, :map => "function(doc) { if (doc.created_at) {emit(doc.created_at.substr(26,4) + ' ' + doc.created_at.substr(4,9), doc); }}"

	def self.from_hash hash
		Tweet.new hash.slice(*@@properties).merge(:from_screen_name => hash["user"]["screen_name"])
	end

	def to_hash
		h = {}
		@@properties.each do |p|
			h[p] = self.send p
		end	
		p
	end


	def mentioned_users
		usernames = extract_mentioned_screen_names(text)
		extract_reply_screen_name(text) do |user|
			usernames << user
		end
		usernames.uniq
	end
	
	def to_json_object
		JSON.parse self.to_json
	end
end

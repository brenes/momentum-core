require 'models/user_report'

class User < CouchRest::Model::Base

	use_database CouchRest.new("http://localhost:5984").database("users")

  	property :nick
  	property :velocity
	property :reports, [UserReport]
	property :profiles, [Hash]

end

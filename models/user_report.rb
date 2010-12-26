class UserReport < Hash

	include CouchRest::Model::CastedModel

	property :time
	property :mentions, Integer, :default => 0
	property :followers, Integer, :default => 0
	property :acceleration, Integer, :default => 0
	property :velocity, Integer, :default => 0

end

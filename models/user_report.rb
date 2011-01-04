class UserReport < Hash

	include CouchRest::Model::CastedModel

	property :time
	property :mentions, Integer, :default => 0
	property :followers, Float, :default => 0
	property :acceleration, Float, :default => 0
	property :velocity, Float, :default => 0

end

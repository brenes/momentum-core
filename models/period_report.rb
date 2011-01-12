class PeriodReport < CouchRest::Model::Base

	use_database CouchRest.new("http://localhost:5984").database("period_reports")

	property :time
	property :mentions, Integer, :default => 0
	property :average_followers, Integer, :default => 0
	property :average_acceleration, Integer, :default => 0
	property :average_velocity, Integer, :default => 0
	property :sorted_users, [Hash]

end

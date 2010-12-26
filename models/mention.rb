class Mention < CouchRest::Model::Base 

	use_database CouchRest.new("http://localhost:5984").database("mentions")

	property :user
	property :created_at

	view_by :hour, :map => "function(doc) { emit(doc.created_at.substr(26,4) + ' ' + doc.created_at.substr(4,9), doc.user); }"

end

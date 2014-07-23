require 'sinatra'
require 'yaml'
require 'mongo'
require 'json'

include FileUtils::Verbose

config = YAML.load_file('config.yml')
client=::Mongo::MongoClient.new(config["mongodb"]["host"], config["mongodb"]["port"])
db=client.db(config["mongodb"]["db"])
trials_collection=db[config["mongodb"]["trials_collection"]]

Dir.mkdir(config["cache_folder"]) unless File.exists?(config["cache_folder"])


get '/dataset/:project_name/:experiment_name/:data_stream?.?:format?' do
	trial_query={__project: params["project_name"], __experiment: params["experiment_name"]}
	trial_query.merge!(params.reject {|k,v| ["experiment_name","project_name","format", "splat","captures","data_stream"].include? k })
	trial_query[:__success]=1

	data_stream=params["data_stream"] || default

	puts trial_query

	trials=trials_collection.find(trial_query).sort(:__timestamp => :desc)
	if trials.count > 0
		latest_trial = trials.first
		id=latest_trial["_id"]
		puts "Returning #{id}"
		filename="#{id.to_s}-#{data_stream}.csv"
		path=File.join(config["cache_folder"], filename)
		
		if File.exists? path
			send_file path, filename: filename, type: "text/csv"
		end
	else
		404
	end 
end

post '/create_trial' do 
	
	request.body.rewind
    request_payload = JSON.parse request.body.read


    request_payload["__timestamp"]=Time.parse(request_payload["__timestamp"])
    
	trial_id=trials_collection.insert(request_payload)
	puts "Trial created: #{trial_id}"
	trial_id.to_s
end

post '/upload_datastream' do 
	trial_id=params["trial_id"]
	data_stream=params["data_stream"]

    tempfile = params["file"][:tempfile] 
    puts "Uploading #{trial_id}-#{data_stream}. Tempfile size: #{File.size(tempfile.path)}"
    new_path=File.join(config["cache_folder"], "#{trial_id.to_s}-#{data_stream}.csv")
    
    cp(tempfile.path, new_path) unless File.exists? new_path
end

post '/set_success' do 
	trial_id=params["trial_id"]
	result=trials_collection.update({"_id" => BSON::ObjectId(trial_id)}, {"$set" => {"__success" => 1}})
	puts "Setting #{trial_id} to success. Result: #{result}"
end
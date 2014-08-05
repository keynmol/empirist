require 'sinatra'
require 'yaml'
require 'mongo'
require 'json'
require 'slim'

include FileUtils::Verbose

if File.exists? "config.yml"
	config = YAML.load_file('config.yml')
else
	config=YAML.load_file('config.example.yml')
end

if ENV['OPENSHIFT_DATA_DIR']
	config['cache_folder']=ENV['OPENSHIFT_DATA_DIR']
end




if !ENV['OPENSHIFT_MONGODB_DB_URL']
	client=::Mongo::MongoClient.new(config["mongodb"]["host"], config["mongodb"]["port"])
	db=client.db(config["mongodb"]["db"])
else
	# db = URI.parse(ENV['OPENSHIFT_MONGODB_DB_URL'])
	# db_name = db.path.gsub(/^\//, '')
	db_name="empirist"
	client = Mongo::Connection.new(ENV['OPENSHIFT_MONGODB_DB_HOST'], ENV['OPENSHIFT_MONGODB_DB_PORT']).db(db_name)
	client.authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'], ENV['OPENSHIFT_MONGODB_DB_PASSWORD']) unless ENV['OPENSHIFT_MONGODB_DB_URL'].nil?

	db=client
end


trials_collection=db[config["mongodb"]["trials_collection"]]

class String
  def is_number?
    true if Float(self) rescue false
  end
end

def generate_selectors(col, selector)
	trials=col.find(selector)
	puts trials.count

	selector={}
	selector_labels={}

	trials.each do |trial|
		trial.each {|k, v|
			unless k.start_with?("_")
				selector[k]||=[]
				v_old=v
				v=Float(v) if v.is_number?
				selector_labels[k]||={}
				selector_labels[k][v]=v_old

				selector[k]<<v unless selector[k].include?(v)
			end
		}
	end

	selector.map{|k,v| v.sort!}

	[selector,selector_labels]
	
end

cache_folder=config["cache_folder"]

Dir.mkdir(cache_folder) unless File.exists?(cache_folder)

get '/' do
	redirect '/projects'
end

get '/projects' do
	@projects=trials_collection.find.map{|t| t["__project"]}.uniq
	slim :projects
end

get '/project/:project' do
	trial_query={__project: params["project"]}
	@experiments=trials_collection.find(trial_query).map {|t| t["__experiment"]}.uniq
	@project=params["project"]
	slim :experiments
end

get '/project/:project/experiment/:experiment' do
	trial_query={__project: params["project"], __experiment: params["experiment"], __success: 1}
	@experiment=params["experiment"]
	@project=params["project"]
	@trials=trials_collection.find(trial_query).sort(:__timestamp => :desc).limit(20)

	slim :trials
end

get '/project/:project/experiment/:experiment/select' do
	full_query={__project: params["project"], __experiment: params["experiment"], __success: 1}
	@active_query=full_query.merge(params.reject {|k,v| ["experiment","project", "splat","captures"].include? k })

	@experiment=params["experiment"]
	@project=params["project"]
	# @trials=trials_collection.find(trial_query).sort(:__timestamp => :desc).limit(20)

	@full_selector, @full_labels=generate_selectors(trials_collection, full_query)
	@active_selector, @active_labels=generate_selectors(trials_collection, @active_query)

	@selector_labels=@full_labels

	@trials=trials_collection.find(@active_query).sort(:__timestamp => :desc).limit(10)

	slim :select_trials
end

get '/annotation/:id' do
	@trial=trials_collection.find_one({"_id" => BSON::ObjectId(params["id"])})
	options=@trial.reject{|k,v| k.start_with?("__") || k.start_with?("_") }

	options.map{|k,v| "#{k}=#{v}"}.join(", ")

end

get '/trial/:trial_id' do
	@trial=trials_collection.find_one({"_id" => BSON::ObjectId(params["trial_id"])})
	@project=@trial["__project"]
	@experiment=@trial["__experiment"]

	@datasets=Dir.glob(cache_folder+"/#{@trial['_id']}-*.csv")
	left=(cache_folder+"/#{@trial['_id']}-").length
	@datasets.map!{|ds| ds[left..-5]}
	@plots=Dir.glob(cache_folder+"/#{@trial['_id']}-*.pdf")
	@plots.map!{|pl| pl[left..-5]}

	slim :trial
end



get '/dataset_by_id/:id/:data_stream' do
	id=params["id"]
	data_stream=params["data_stream"]
	filename="#{id.to_s}-#{data_stream}.csv"
	path=File.join(cache_folder, filename)
	
	if File.exists? path
		send_file path, filename: filename, type: "text", disposition: "inline"
	else
		404
	end
end

get '/plot_by_id/:id/:plot_name' do
	id=params["id"]
	plot_name=params["plot_name"]
	filename="#{id.to_s}-#{plot_name}.pdf"
	path=File.join(cache_folder, filename)
	puts path
	
	if File.exists? path
		send_file path, filename: filename, type: "application/pdf", disposition: "inline"
	else
		404
	end
end

get '/find_trial/:project_name/:experiment_name' do
	trial_query={__project: params["project_name"], __experiment: params["experiment_name"]}
	trial_query.merge!(params.reject {|k,v| ["experiment_name","project_name","format", "splat","captures","data_stream"].include? k })
	trial_query[:__success]=1

	trials=trials_collection.find(trial_query).sort(:__timestamp => :desc)
	
	if trials.count > 0
		trials.first["_id"].to_s
	else
		404
	end 
end



get '/dataset/:project_name/:experiment_name/:data_stream?.?:format?' do
	trial_query={__project: params["project_name"], __experiment: params["experiment_name"]}
	trial_query.merge!(params.reject {|k,v| ["experiment_name","project_name","format", "splat","captures","data_stream"].include? k })
	trial_query[:__success]=1

	data_stream=params["data_stream"] || "default"

	trials=trials_collection.find(trial_query).sort(:__timestamp => :desc)
	puts trial_query
	if trials.count > 0
		latest_trial = trials.first
		id=latest_trial["_id"]

		redirect "/dataset_by_id/#{id}/#{data_stream}"
	else
		404
	end 
end

get '/plot/:project_name/:experiment_name/:plot_name?.?:format?' do
	trial_query={__project: params["project_name"], __experiment: params["experiment_name"]}
	trial_query.merge!(params.reject {|k,v| ["experiment_name","project_name","format", "splat","captures","plot_name"].include? k })
	trial_query[:__success]=1

	plot_name=params["plot_name"]

	trials=trials_collection.find(trial_query).sort(:__timestamp => :desc)

	if trials.count > 0
		latest_trial = trials.first
		id=latest_trial["_id"]

		redirect "/plot_by_id/#{id}/#{plot_name}"
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
    
    trial=trials_collection.find_one({"_id" => BSON::ObjectId(trial_id)})
    trial["__datastreams"]||=[]
    trial["__datastreams"]<<data_stream unless trial["__datastreams"].include? data_stream
    trials_collection.update({"_id" => BSON::ObjectId(trial_id)}, trial)
    

    puts "Uploading #{trial_id}-#{data_stream}. Tempfile size: #{File.size(tempfile.path)}"
    new_path=File.join(cache_folder, "#{trial_id.to_s}-#{data_stream}.csv")
    
    cp(tempfile.path, new_path) unless File.exists? new_path
end

post '/upload_plot' do
	trial_id=params["trial_id"]
	plot_name=params["plot"]


    tempfile = params["file"][:tempfile] 

    trial=trials_collection.find_one({"_id" => BSON::ObjectId(trial_id)})
    trial["__plots"]||=[]
    trial["__plots"]<<plot_name unless trial["__plots"].include? plot_name
    trials_collection.update({"_id" => BSON::ObjectId(trial_id)}, trial)
    
    puts "Uploading #{trial_id}-#{plot_name}. Tempfile size: #{File.size(tempfile.path)}"
    new_path=File.join(cache_folder, "#{trial_id.to_s}-#{plot_name}.pdf")

    cp(tempfile.path, new_path)

end

post '/set_success' do 
	trial_id=params["trial_id"]
	result=trials_collection.update({"_id" => BSON::ObjectId(trial_id)}, {"$set" => {"__success" => 1}})
	puts "Setting #{trial_id} to success. Result: #{result}"
end
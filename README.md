# Current vision

Suppose, we have a research team. We run a central server which stores results of all experiments and all plots. Every researcher additionally runs an empirist-agent for backwards communication between server and researcher.
Those results and plots are generated using Python and Ruby scripts using packages *empirist-python* and *empirist-ruby* respectively. We call those scripts *experiments*. They publish their results(essentially, CSV files) along with experiment parameters which generated these results on this server. Each experiment can produce several different **data streams** - essentially, different datasets depending on what data we want to store.

So, when we want to perform analysis, we specify the experiment which *we want to have* using an URL, e.g. 
http://empirist-server.com/ProjectName/ExperimentName/error_function.csv?learning_rate=0.01&weight_decay=0.1&function=mackey-glass will return a regular CSV file.

This makes everything easier. In analysis and publication tools we only specify the parameters of datasets we want to analyse or plot. The system will automatically retrieve the most up-to-date trial with those parameters, or send a message to appropriate empirist-agent to generate such dataset.

Parameters can be either directly specified in the experiment code(see **Parameters** section below), or be picked up by system from environment(git branch/revision, for example, to compare different versions of algorithm).

## Actually working example.
### Setup
#### Server
First, we need an Empirist Server running(main node in our star-like network. There's already a server running on the Internet(e.g. http://empirist.herokuapp.com/project/FunctionalInputDetecting/experiment/HiddenUnitImportance), so its host would be `empirist.herokuapp.com`, and port `80`.
#### Agent
Empirist Agent is an entity that runs on researcher's computer -- it's completely local to that machine and all the interactions are transparent for researcher as they go through Agent which then redirects them to Server, if necessary. If the agent is up and running there's no need to touch it until it needs to be re-configured. Neat.

So we open Agent's folder and put those lines in `config.yml`:
```yaml
empirist_server:
 host: empirist.herokuapp.com
 port: 80
cache_folder: /tmp/empirist-cache
```
Pretty straightforward. Folder `/tmp/empirist-cache` will be created if it doesn't exists. After this we can launch it: `ruby agent.rb -p 5050` - this will launch Empirist Agent on port **5050**.

#### Experiment
We just write an experiment code in Ruby(should be understandable if you know Python):
```ruby
require 'empirist'
include Empirist

class TestExperiment < Experiment
	def configure
		# project name(duh)
		project_name "TestProject"

		# add parameters which will be automatically picked up from
		# command line or replaced with default if absent
		add_parameter "shift", 0.5
		add_parameter "timesteps", 1000
		
		# data we want to record: scheme and stream name
		data_stream ["Timestep", "Input"], "inputs"
		data_stream ["Timestep", "Value"], "value_function"
	end

	# the experiment itself
	def experiment
		# we are just executing cos(x+y) at each timestep and record it.
		# x and y are generated randomly
		parameters.timesteps.times do |timestep|

			input = [rand - parameters.shift, rand - parameters.shift]
			value = Math.cos(0.311*input[0] + 0.421*input[1])

			observation [timestep, input], "inputs"
			observation [timestep, value], "value_function"

		end
	end
end

# run the experiment!
TestExperiment.new(agent: "localhost:5050").execute
```
Put this code into a file called `TestExperiment.rb`(name doesn't really matter) and then just run it: `ruby TestExperiment.rb`. And so the magic starts.
After the execution is finished we can go to <http://empirist.herokuapp.com/project/TestProject/experiment/TestExperiment> and see something like this:
![](http://i.imgur.com/TXGC1TB.png)

Fantastic! Our trial was recorded on the server. The generated datasets are also there! If we click on one of the Datasets links(say value_function), we'll get a regular CSV file with a following structure:

| Run | Timestep | Value              |
|-----|----------|--------------------|
| 0   | 0        | 0.9612958445716469 |
| 0   | 1        | 0.9990226401152685 |
| 0   | 2        | 0.9952891265769941 |
| 0   | 3        | 0.9931870280330792 |
| 0   | 4        | 0.9724751090407721 |
| 0   | 5        | 0.9733155048352489 |
| 0   | 6        | 0.9918385394588366 |
| 0   | 7        | 0.9999999950712188 |
| 0   | 8        | 0.9626322551295595 |
| 0   | 9        | 0.9982273545957638 |
| 0   | 10       | 0.9775562148294717 |
| 0   | 11       | 0.9855737113344184 |
| 0   | 12       | 0.9433655108185586 |
| 0   | 13       | 0.9479736498012329 |
| 0   | 14       | 0.9794239501839925 |
| 0   | 15       | 0.9946875540224025 |

Exactly what we specified in Experiment's description, apart from the Run column(you can disable it, but it's handy).

This means we can easily retrieve this data. Let's plot something. I'll use R for demonstration, so if you don't know it, just read the commented lines and try to understand the code.

After skipping all the libraries loading, we end up with this code:
```R
# again, we connect to the agent
empirist<-connectToEmpirist("localhost",5050)

# select experiment by project name and experiment name
experiment<-getExperiment(empirist, 
                          "TestProject", 
                          "TestExperiment")


# this just DEFINES a plot with a certain name, without actually executing anything.
addPlot(experiment, "distribution", 
        function(trial){
          distributions <- getDataset(trial, stream="inputs")
          distributions <- melt(distributions, id=c("Timestep", "Run"))
          
          (ggplot(distributions, aes(x=value, fill=variable)) + ggtitle("Variables distribution")
           +scale_y_continuous("")
           +geom_density(alpha=0.6))
        })
addPlot(experiment, "function", 
        function(trial){
          values <- getDataset(trial, stream="value_function")
          
          (ggplot(values, aes(x=Timestep, y=Value))+geom_line() + ggtitle("Value function"))
        })


# This will just select latest trial in the experiment, but we can specify all the necessary parameters
trial <- getTrial(experiment)

# this will create the plot, show it and send it to the server.
showAndSavePlot(experiment, trial, "distribution")
showAndSavePlot(experiment, trial, "function")
```
That's it. After running it, the previously visited page, http://empirist.herokuapp.com/project/TestProject/experiment/TestExperiment, has changed a bit:
![](http://i.imgur.com/57z1KYV.png) - the Plots section has been added to the trial. Now, if we click on those links, we'll see beautifully rendered plots associated with this particular trial and data generated by it:

<http://empirist.herokuapp.com/plot_by_id/53d50a92bb24010002000003/distribution>
![](http://i.imgur.com/2PIIc0p.png)

<http://empirist.herokuapp.com/plot_by_id/53d50a92bb24010002000003/function>
![](http://i.imgur.com/laSja9z.png)

And of course we can change parameters from the command line: `ruby TestExperiment.rb --timesteps 5000`.

What makes it good for publication is that we can reference plots by URL: `http://empirist.herokuapp.com/plot/TestProject/TestExperiment/distribution?timesteps=1000` with parameters and other stuff, directly in LaTeX document. Well, almost directly, we need to define a new command:
```
\newcommand{\urlFigure}[2]{ \write18{wget -O #2 #1 } \includegraphics{#2}}
...
\begin{figure}[h!]
\urlFigure{http://empirist.herokuapp.com/plot/TestProject/TestExperiment/distribution?timesteps=1000}{testerrors.pdf}
\caption{Cool, huh?}
\end{figure}
```
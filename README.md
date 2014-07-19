# Current vision

Suppose, we have a research team. We run a central server which stores results of all experiments and all plots. Every researcher additionally runs an empirist-agent for backwards communication between server and researcher.
Those results and plots are generated using Python and Ruby scripts using packages *empirist-python* and *empirist-ruby* respectively. We call those scripts *experiments*. They publish their results(essentially, CSV files) along with experiment parameters which generated these results on this server. Each experiment can produce several different **data streams** - essentially, different datasets depending on what data we want to store.

So, when we want to perform analysis, we specify the experiment which *we want to have* using an URL, e.g. 
http://empirist-server.com/ProjectName/ExperimentName/error_function.csv?learning_rate=0.01&weight_decay=0.1&function=mackey-glass will return a regular CSV file.

This makes everything easier. In analysis and publication tools we only specify the parameters of datasets we want to analyse or plot. The system will automatically retrieve the most up-to-date trial with those parameters, or send a message to appropriate empirist-agent to generate such dataset.

Parameters can be either directly specified in the experiment code(see **Parameters** section below), or be picked up by system from environment(git branch/revision, for example, to compare different versions of algorithm).

So in R we would write something like this: 

```R
#                            project name       experiment        parameters
trial<-get_trial("FunctionalInputDetecting", "CorrelatedNoise", list(target_function="TripleSine",
                                                                               predictor_type="NeuralNetwork",
                                                                               hidden_neurons=5,
                                                                               timesteps=5000,
                                                                               runs=10, 
                                                                               distractors_per_input=2,
                                                                               gaussian_noise_variance=0,
                                                                               gaussian_noise_mean=0
                                                                               ))
```
Specifying only the parameters of a trial that we want to analyse. This approach also makes it a lot easier to perform contrast analysis for a certain parameter(to see how the system behaves depending on various values of one parameter with others being fixed) - we just need to change one parameter in a list and most analysis tools will make it as easy as possible.

This can go even further and be extended to plotting -- if experiments produce datasets, then why can't we produce plots? We can reference plots by URL specifying meta-parameters such as width, height and format and reference those plots in a LaTeX document by URL(there are packages that can do that easily). Using ConTeXt package we would specify 

```LaTeX
externalfigure[http://empirist-server.com/ProjectName/ExperimentName/error_function.pdf?learning_rate=0.01&weight_decay=0.1&function=mackey-glass&_width=5cm&_height=5cm]
```
and the system will generate a PDF plot with specified experiment parameters(internally those parameters will just be passed to a function which looks up specific dataset used by plot) and then generate a plot using various meta-parameters. 

Of course this will have some bells and whistles - for example we should be able to specify multiple values for some of the parameter and a meta-parameter that tells the system how to handle multiple plots. For example, *_side_by_side* or *_group_by* or something like this.


# Research environment with self-organising experiment results.

**TL;DR**

Result=Experiment(Parameters)

Result=(Observation, Observation, Observation, ...)

Observation=(State 1, State 2, State 3, Measurement, Measurement, ...)

Quick and easy access to all (Parameters, Result) pairs for further analysis.

Reduce worrying about naming data files, storing them and checking their consistency.

Convention over Configuration.

## Goal
To minimise the hassle of managing dozens of datafiles for all the various experiments 

## Experiment
Some code that produces certain data. This data will depend on experiment's Conditions(or Parameters).
We usually want to produce plots that compare data obtained under different conditions.
Problem - storing and organising results of experiments. At any point in time we want to have a full access to all experimental results with a nice and easy to understand view of parameters for each result. 

So the setup will be as following: we launch Experiment, it produces some data depending on Parameters. Those results are stored in a CSV file, which location and name is decided by the Environment.

Each set of Parameters is assigned a unique ID and CSV file's name will have the format of ExperimentName_***id***.csv

## Parameters
They include all the values of console parameters(specified in the definition of the experiment), for example:

```python
class TestPredictors(Experiment):
	def configure(self):		
		# experiment global parameters
		self.add_parameter("timesteps", 100)
		self.add_parameter("test_size",100)
		self.add_parameter("predictor_type", "ols")
		self.add_parameter("hidden_neurons", 5)
```

We specify default value for each parameter. This is only part of the recorded Parameters, as we can add things like version control system revision for more elegant tracking of algorithm/code changes and their effect on the experiment results.

So just having experiment name and launch ID we can get full list of Conditions from the system and datafile location for further analysis.


## Example
**Experiment**: studying how good neural networks and Online Least Squares learners are at different non-linear and linear tasks in an online learning environment. Each 10 timesteps we train our chosen optimiser and test it on a dataset. Our predictors are trying to learn functions identified by **second_squared** and **mult**.


**Parameters**:

 - We have two different types of predictor - **ols** and **nn**. Default: "ols".
 - We can vary number of timesteps. Default: 100.
 - We can vary the size of test dataset. Default: 100
 - We can vary the number of runs(for averaging test error, for example). Default: 1.
 - For **nn** predictors we can vary the number of hidden neurons. Default: 5.

So, if we put our experiment in file called `TestPredictors.py` and launch it like this: `python TestPredictors.py --timesteps 500 --predictor_type nn` this experiment's parameters description will look something like this: `predictor_type=nn,timesteps=500,test_size=100,runs=1,hidden_neurons=5`. As you can see, defaults were used in place of missing values.

If any VCS is used, revision number and time of launch will also be added to the string of parameters, making it a unique identifier.


**Example experiment results**:

| Timestep | Function       | Run | Error          |
|----------|----------------|-----|----------------|
| 10       | second_squared | 0   | 1.8391515947   |
| 20       | second_squared | 0   | 1.26634650666  |
| 30       | second_squared | 0   | 1.26518162943  |
| 10       | mult           | 0   | 0.890239930739 |
| 20       | mult           | 0   | 0.804060888098 |
| 30       | mult           | 0   | 0.774142038184 |

We are also making a distinction between **Parameters** and **States** -- parameters are affecting the execution of Experiment, while states are actually being recorded in the final **Report**. Sometimes parameters and states have seemingly overlapping names.

In the example results above we have six Observations - they form the dataset recorded in the CSV file. As you can see, parameters are not included in this dataset. **State** candidates here are Timestep, Function and Run - because many observations share them. Those variables will probably be used for grouping in subsequent analysis.

### Code
Now we will outline the code necessary for this example.

```python
from experiment import *

class TestPredictors(Experiment):
	def configure(self):		
		# PARAMETERS configuration
		self.add_parameter("timesteps", 100)
		self.add_parameter("test_size",100)
		self.add_parameter("predictor_type", "ols")
		self.add_parameter("hidden_neurons", 5)
 	
		# STATE CONFIGURATION
		self.add_state("Timestep", 0)
		self.add_state("Function", None)

		# what exactly we want to report at each stage
		self.data_stream(["Error"])
```
This code will setup command line argument parser to accept parameters and report-writing engine to acknowledge the addition of two states(Timestep and Function) to each observation. _**Run** state is added to the report automatically!_

Next we setup the process of experiment, which consists of three stages executed in that particular order:

 - **Pre-experiment** - any setup that we need to perform before each run.
 	In this example we need to re-initialise the predictor.
 
```python
	def pre_experiment(self):		
		# initialise predictor
		if self.options.predictor_type=="nn":
			self.predictor=NNPredictor(2,1,hidden=self.options.hidden_neurons)
		else:
			self.predictor=OSLPredictor(2,1)

```
 - **Experiment** - we will not provide full code here for the experiment, but some important points have to be made.

	The experiment run might change certain states, which can be done using following line:
 
```python
def experiment(self):
	...
	self.set_state("Function", _new value_)
	...
```
And when we need to make an observation, we use a line like this:

```python
	self.observation([self.error(self.predictor, test_dataset)])
```
 
 - **Post-Experiment** - executed after each run. In this example we don't need to do anything.

```python
	def post_experiment(self):
		pass
```

After the experiment class has been properly defined, the only line required is this one:
```python
TestPredictors(description="testing predictors generalisation ability").execute()
```
which creates an experiment instance and runs it.

## Aid in Analysis
Requires further clarification, but here's what we're trying to achieve:
a package for each of the main analytical tools which helps retrieve experiment's datafile based on values of parameters.

So we turn something like 

```R
dataset<-read.csv("../../../predictors_tst100_timesteps100_1a.csv")
``` 

to 

```R
dataset<-read.csv(GetData("TestPredictors", list(test_size=100, timesteps=100)))
``` 

Following "convention over configuration" principle all the way through analysis.

**Most importantly, it's not an attempt to create a new analysis tool, it's an attempt to better organise classical research pipeline in an environment familiar to many researchers**


## Future
Have a web-interface that 

 - shows all past experiments with information(every time we run an experiment it appears in the database)
 - allows re-running outdated experiments
 - allows running sequences of experiments(for example, "Run TestPredictors with hidden layer size ranging from 5 to 20")
 - launches experiments on different associated machines(with automatic copying/updating of source code and collecting of results)
 - can show progress for each of the running experiments.
 - has automated plotting! We associate different plotters(e.g. gnuplot, R plotting scripts) with experiments and can create plots that compare different configurations of the same experiment.
 - can deal with user-defined summarisation functions(for our example, average error on all functions at the end of timeline) - which can be used to compare different parameters of experiments.
 - Plotting should be done via URL - we specify which plot we want to show in a form like  [http://localhost:3000/plot/TestPredictors?timesteps=1000&plotter=ErrorPlot&__git_branch=master](#) and the system will automatically generate non-existent plot and return, say, a PNG file with desired plot. This way we can keep all the plots up-to-date and not worry about referencing them.

## Even farther future
Integrate all this into a complete and generalised data-processing pipeline with all the commercial candy stuff included - Hadoop, Pig, Big Data etc.
And then sell it to Netflix.

## Development setup
All significant pieces of code should be organised into python packages from the very beginning(it's easy and helps code distribution **A LOT**).
So every module is being developed in its own directory where we run `watchmedo shell-command --patterns="*.py;" --recursive --command='python setup.py install'`


## Technical details
One main class which inherits from superclass Experiment. 
Using a not yet finished Reporting library to abstract writing directly to CSV files. Make it handle types properly, arrays of values and multiple **Streams** - one experiment can produce several different datafiles, depending on data being posted to the stream. But as we're following CoC, default stream is always implied.

All of this should be highly customisable though.

As the number and types of parameters can vary, data structure for finding experiments' IDs looks schema-less. In comes MongoDB! It has drivers for both Matlab and R, two of the most popular IDEs for research. It obviously has a driver for nearly every single programming language out there, but Python would be of most interest for us right now.

## Appendix A. Example code
This is code for a slightly different experiment, but still structure is all the same. It produces datasets like this:

| Timestep | Function       | Run | Error          | Weight0          | Weight1          | Bias0          |
|----------|----------------|-----|----------------|------------------|------------------|----------------|
| 10       | second_squared | 0   | 1.8391515947   | -0.486987659621  | 0.888535018412   | 0.703820867166 |
| 20       | second_squared | 0   | 1.26634650666  | -0.227607834684  | 0.0321685130545  | 0.870916360616 |
| 30       | second_squared | 0   | 1.26518162943  | -0.103265780233  | 0.211615479252   | 1.06581244238  |
| 40       | second_squared | 0   | 1.23517667267  | -0.0474367210353 | 0.032732083004   | 1.11890454959  |
| 50       | second_squared | 0   | 1.23739016603  | -0.132314906453  | 0.0228663436296  | 1.04887913149  |
| 60       | second_squared | 0   | 1.22945206001  | -0.0346485360724 | -0.0798603038087 | 1.03108537894  |
| 70       | second_squared | 0   | 1.23523317338  | -0.110891307711  | 0.0280900458811  | 1.03696089086  |
| 80       | second_squared | 0   | 1.23517401791  | -0.091643082047  | 0.0413347721603  | 0.996126081987 |
| 90       | second_squared | 0   | 1.24103674368  | -0.114830521623  | 0.0773221771705  | 0.99149723377  |
| 10       | mult           | 0   | 0.890239930739 | -0.246238979683  | 0.184015683584   | 0.922617920377 |
| 20       | mult           | 0   | 0.804060888098 | -0.274393107143  | 0.180883818927   | 0.80840759804  |
| 30       | mult           | 0   | 0.774142038184 | -0.257998978287  | 0.180838893775   | 0.779135577405 |
| 40       | mult           | 0   | 0.751555354569 | -0.300265613368  | 0.194770172251   | 0.719826433351 |
| 50       | mult           | 0   | 0.727806345712 | -0.31206176033   | 0.180730957669   | 0.682102495408 |
| 60       | mult           | 0   | 0.711110792408 | -0.311167308606  | 0.176675597631   | 0.658828804337 |
| 70       | mult           | 0   | 0.694461589749 | -0.283944647074  | 0.151695129232   | 0.658921799528 |
| 80       | mult           | 0   | 0.669237876725 | -0.271566913172  | 0.145678290888   | 0.628923081672 |
| 90       | mult           | 0   | 0.653789381593 | -0.268685597526  | 0.13312571755    | 0.608655258669 |

Notice how Reporting automatically handles array values passed to "Weight" and "Bias" columns.

```python
from experiment import *
from predictor import *
import math

funcs={"cos_sum": lambda inputs: math.cos(inputs[0]+inputs[1]),
					"sum": lambda inputs: (inputs[0]+inputs[1]),
					"cos_first": lambda inputs: math.cos(inputs[0]),
					"cos_second": lambda inputs: math.cos(inputs[1]),
					"random": lambda inputs: random.gauss(0,1),
					"mult": lambda inputs: inputs[0]*inputs[1],
					"first_squared": lambda inputs: inputs[0]**2,
					"second_squared": lambda inputs: inputs[1]**2
				}

class TestPredictors(Experiment):
	def configure(self):
		# internal runs configuration
		self.add_run=True
		self.runs=1 # this will be used unless --runs parameter is specified explicitly
		
		# experiment global parameters
		self.add_parameter("timesteps", 100)
		self.add_parameter("test_size",100)
		self.add_parameter("predictor_type", "ols")
		self.add_parameter("hidden_neurons", 5)
 	
		# parameters that we're willing to change during experiment.
		# we call them states
		self.add_state("Timestep", 0)
		self.add_state("Function", None)

		# what exactly we want to report at each stage
		self.data_stream(["Error","Weight","Bias"])

	
	#executed before each experiment run
	def pre_experiment(self):		
		# initialise predictor
		if self.options.predictor_type=="nn":
			self.predictor=NNPredictor(2,1,hidden=self.options.hidden_neurons)
		else:
			self.predictor=OSLPredictor(2,1)


	#main logic goes here
	def experiment(self):
		experiment_options=self.options
		for f in funcs:
			self.set_state("Function", f)
			# create test dataset
			test_dataset=[]
			for n in range(self.options.test_size):
				inp=[random.gauss(0,1) for i in range(2)]
				out=np.array([funcs[f](inp)])
				test_dataset.append([inp,out])

			for timestep in range(experiment_options.timesteps):
				self.set_state("Timestep",timestep)
				
				inp=[random.gauss(0,1) for i in range(2)]
				out=np.array([funcs[f](inp)])

				value=self.predictor.compute_value(inp)
				self.predictor.save_point(inp,out)
				self.predictor.train()

				inputs=self.predictor.input_fitnesses(normalised=False)
				biases=self.predictor.bias_fitnesses(normalised=False)
				
				if self.predictor.ready() and timestep % self.predictor.dataset_size() == 0 and timestep>1:
					self.observation([self.error(self.predictor, test_dataset), inputs, biases])

	#executed after each run
	def post_experiment(self):
		pass

	# miscellaneous functions
	def error(self, model, dataset):
		res=0
		for i, o in dataset:
			res+=(model.compute_value(i)[0]-o[0])**2
		return res/(2*len(dataset))



TestPredictors(description="testing predictors generalisation ability").execute()
```
from collections import OrderedDict
import numpy as np


class ReportWriter():
	def __init__(self):
		self.streams=[]
		self.params=[]

	def addStream(self, stream, name):
		self.streams.append([stream,name])

	def addParameter(self, param):
		self.params.append([param,param.name])

	def finish(self):
		pass

class CSVWriter(ReportWriter):
	def __init__(self, filenameTemplate):
		ReportWriter.__init__(self)
		self.nameTemplate=filenameTemplate
		self.files={}

	def addStream(self,stream,name):
		pass
		# self.files[name]=open(self.nameTemplate % {'stream':name},"w")
		# self.files[name].write(";".join([p[1] for p in self.params]+stream.scheme)+"\n")

	def record(self, streamName, data):
		data_line=";".join([str(d[1]) for d in data])
		if streamName not in self.files:
			self.open_file(streamName)

		if self.files[streamName][1]==False:
			header_line=";".join([str(d[0]) for d in data])
			self.files[streamName][0].write(header_line+"\n")
			self.files[streamName][1]=True

		self.files[streamName][0].write(data_line+"\n")

	def open_file(self, name):
		self.files[name]=[open(self.nameTemplate % {'stream':name},"w"), False]

	def finish(self):
		for f,name in enumerate(self.files):
			self.files[name][0].close()

class MemoryWriter(ReportWriter):
	def __init__(self, memoryObject, streamsMapping):
		ReportWriter.__init__(self)
		self.memoryObject=memoryObject
		self.streamsMapping=streamsMapping
		self.dupStreams={}
		self.caping={}
		self.initMapping()

	def initMapping(self):
		for k in self.streamsMapping:
			self.caping[k]=-1
			if not k in self.memoryObject:
				self.memoryObject[k]={}
				for p in self.streamsMapping[k]:
					self.memoryObject[k][p]=np.zeros(0)

	
	def setCaping(self,streamName, cap):
		self.caping[streamName]=cap

	def addDuplicateStream(self, streamName, dupStreamName):
		self.dupStreams[dupStreamName]=streamName
		self.streamsMapping[streamName]=self.streamsMapping[dupStreamName]
		self.initMapping()


	def addStream(self,stream,name):
		pass

	def record(self, streamName, data):
		affectedStreams=[streamName]
		if streamName in self.dupStreams:
			affectedStreams.append(self.dupStreams[streamName])
		# print affectedStreams
		for stream in affectedStreams:
			if stream in self.streamsMapping:
				for r in data:
					if r[0] in self.streamsMapping[stream]:
						aa=self.memoryObject[stream][r[0]]

						if len(aa)==self.caping[stream] and self.caping[stream]!=-1:
							self.memoryObject[stream][r[0]]=np.roll(aa,-1)
							self.memoryObject[stream][r[0]][self.caping[stream]-1]=r[1]
						else:
							self.memoryObject[stream][r[0]]=np.append(aa,r[1])


class ConsoleWriter(ReportWriter):
	pass


class Param():
	def __init__(self, attrName, value):
		self.name=attrName
		self.value=value
		self.default_value=value
	
	def setValue(self, value):
		self.value=value

	def reset(self):
		self.value=self.default_value

class NoDataStreamError(Exception):
	def __init__(self,value):
		self.value=value
	def __str__(self):
		return "Data stream not found: {0}" % self.value


class Report():
	def __init__(self, writer=None):
		self.parameters=OrderedDict()
		self.streams={}
		self.writers=[]
		self.dependentStreams={}
		self.lastObservations={}
		
		if not writer==None:
			self.writers.append(writer)
		pass

	def addParameter(self, param):
		self.parameters[param.name]=param
		[w.addParameter(param) for w in self.writers]

	def changeParameter(self,name, value):
		self.parameters[name].setValue(value)

	def addWriter(self,writer):
		self.writers.append(writer)

	def synchronise_params(self, writer):
		writer_params=writer.params

	def addStream(self, name, stream):
		self.streams[name]=stream
		self.lastObservations[name]=None
		
		# for writer in self.writers:
		# 	writer.addStream(stream, name)

	def addDependentStream(self, streamName, masterStreamName):
		if not masterStreamName in self.streams:
			raise NoDataStreamError(masterStreamName)
		if not streamName in self.streams:
			raise NoDataStreamError(streamName)

		if not masterStreamName in self.dependentStreams:
			self.dependentStreams[masterStreamName]=[]
		
		self.dependentStreams[masterStreamName].append(streamName)

	def observation(self, streamName, data):
		observation=[]

		if not streamName in self.streams:
			raise NoDataStreamError(streamName)

		stream=self.streams[streamName]

		hob={}
		
		for pname in self.parameters:
			observation.append([pname, self.parameters[pname].value])
			hob[pname]=self.parameters[pname].value

		if isinstance(data,dict):
			for field in stream.scheme:
				if type(data[field])==list:
					for i, v in enumerate(data[field]):
						hob[field+str(i)]=v
						observation.append([field+str(i), v])
				else:
					observation.append([field, data[field]])
					hob[field]=data[field]

		if isinstance(data,list):
			for ind,value in enumerate(data):
				if type(value)==list:
					for i, v in enumerate(value):
						hob[stream.scheme[ind]+str(i)]=v
						observation.append([stream.scheme[ind]+str(i), v])
				else:
					observation.append([stream.scheme[ind], value])
					hob[stream.scheme[ind]]=value

		self.lastObservations[streamName]=hob

		if streamName in self.dependentStreams:
			for stream in self.dependentStreams[streamName]:
				self.observation(stream, self.streams[stream].observation(hob))

		for w in self.writers:
			w.record(streamName, observation)

	def lastObservation(self,streamName):
		return self.lastObservations[streamName]
	
	def finish(self):
		for writer in self.writers:
			writer.finish()
		

class DataStream():
	def __init__(self, scheme):
		self.scheme=scheme
	
	def observation(self,params):
		#test scheme
		pass
	
	def paramsToHash(self,params):
		if type(params)==dict:
			return params
		elif type(params)==list:
			r={}
			for i in enumerate(params):
				r[self.scheme[i]]=params[i]
			return r

class SlidingErrorDataStream(DataStream):
	def __init__(self, scheme):
		self.scheme=scheme
		self.sliding_windows={}
		self.errors={}

	def addError(self,valueParam, predictionParam, saveParam):
		self.errors[saveParam]=[valueParam,predictionParam]
		self.sliding_windows[saveParam]=np.random.rand(10)*0
	
	def rollIn(self,saveParam, value):
		self.sliding_windows[saveParam]=np.roll(self.sliding_windows[saveParam],1)
		self.sliding_windows[saveParam][0]=value
	
	def observation(self, params):
		#test scheme
		h=self.paramsToHash(params)
		ob={}
		for err in self.errors:
			p=self.errors[err]
			self.rollIn(err,(h[p[0]]-h[p[1]])**2)
			ob[err]=np.mean(self.sliding_windows[err])

		return ob
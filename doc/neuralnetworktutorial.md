<a name="NeuralNetworkTutorial"/>
# Neural Network Tutorial #
We begin with a simple [neural network example](../examples/neuralnetwork_tutorial.lua). The first line loads 
the __dp__ package, whose first matter of business is to load its dependencies (see [init.lua](../init.lua)):
```lua
require 'dp'
```
Note : package [Moses](https://github.com/Yonaba/Moses/blob/master/docs/moses.md) is imported as `_`. So `_` shouldn't be used for dummy variables, instead 
use the much more annoying `__`, or whatnot. 

Lets define some hyper-parameters and store them into a table. We will need them later:
```lua
--[[hyperparameters]]--
opt = {
   nHidden = 100, --number of hidden units
   learningRate = 0.1, --training learning rate
   momentum = 0.9, --momentum factor to use for training
   maxOutNorm = 1, --maximum norm allowed for output neuron weights
   batchSize = 128, --number of examples per mini-batch
   maxTries = 100, --maximum number of epochs without reduction in validation error.
   maxEpoch = 1000 --maximum number of epochs of training
}
```
## DataSource and Preprocess ##
We intend to build and train a neural network so we need some data, 
which we encapsulate in a [DataSource](data.md#dp.DataSource)
object. __dp__ provides the option of training on different datasets, 
notably [MNIST](data.md#dp.Mnist), [NotMNIST](data.md#dp.NotMnist), 
[CIFAR-10](data.md#dp.Cifar10) or [CIFAR-100](data.md#dp.Cifar100), but for this
tutorial we will be using the archtypical MNIST (don't leave home without it):
```lua
--[[data]]--
datasource = dp.Mnist{input_preprocess = dp.Standardize()}
```
A DataSource contains up to three [DataSets](data.md#dp.DataSet): 
`train`, `valid` and `test`. The first if for training the model. 
The second is used for [early-stopping](observer/earlystopper.lua) and cross-validation.
The third is used for publishing papers and comparing different models.
  
Although not really necessary, we [Standardize](../preprocess/standardize.lua) 
the datasource, which subtracts the mean and divides 
by the standard deviation. Both statistics (mean and standard deviation) are 
measured on the `train` set only. This is a common pattern when preprocessing data. 
When statistics need to be measured accross different examples 
(as in [ZCA](preprocess.md#dp.ZCA) and [LecunLCN](../preprocess/lecunlcn.lua) preprocesses), 
we fit the preprocessor on the `train` set and apply it to all sets (`train`, `valid` and `test`). 
However, some preprocesses require that statistics be measured
only on each example (as in [global constrast normalization](preprocess.md#dp.GCN)). 

## Model of Modules ##
Ok so we have a DataSource, now we need a [Model](model.md#dp.Model). Lets build a 
multi-layer perceptron (MLP) with two parameterized non-linear [Neural](model.md#dp.Neural) [Layers](model.md#dp.Layer):
```lua
--[[Model]]--
model = dp.Sequential{
   models = {
      dp.Neural{
         input_size = datasource:featureSize(), 
         output_size = opt.nHidden, 
         transfer = nn.Tanh()
      },
      dp.Neural{
         input_size = opt.nHidden, 
         output_size = #(datasource:classes()),
         transfer = nn.LogSoftMax()
      }
   }
}
```
Both layers are defined using [Neural](model.md#dp.Neural), which require an `input_size` 
(number of input neurons), an `output_size` (number of output neurons) and a 
[Transfer](https://github.com/torch/nn/blob/master/doc/transfer.md) Module.
We use the `datasource:featureSize()` and `datasource:classes()` methods to access the
number of input features and output classes, respectively. As for the number of 
hidden neurons, we use our `opt` table of hyper-parameters. The Transfer
[Modules](https://github.com/torch/nn/blob/master/doc/module.md#nn.Module) 
used are the [Tanh](https://github.com/torch/nn/blob/master/doc/transfer.md#nn.Tanh) (for the hidden neurons) 
and [LogSoftMax](https://github.com/torch/nn/blob/master/doc/transfer.md#nn.LogSoftMax) (for the output neurons).
The latter might seem odd (why not use [SoftMax](https://github.com/torch/nn/blob/master/doc/transfer.md#nn.SoftMax) instead?), 
but the [ClassNLLCriterion](https://github.com/torch/nn/blob/master/doc/criterion.md#nn.ClassNLLCriterion) only works 
with LogSoftMax (or with SoftMax + [Log](https://github.com/torch/nn/blob/master/Log.lua)).

Both models initialize parameters using the default sparse initialization 
(see [Martens 2010](http://machinelearning.wustl.edu/mlpapers/paper_files/icml2010_Martens10.pdf)). 
If you construct it with argument `sparse_init=false`, it will delegate parameter initialization to 
[Linear](https://github.com/torch/nn/blob/master/doc/simple.md#nn.Linear), 
which is what Neural uses internally for its parameters.

These two Neural [Models](model.md#dp.Model) are combined to form an MLP using the [Sequential](model.md#dp.Sequential), 
which is not to be confused with (yet very similar to) the 
[Sequential](https://github.com/torch/nn/blob/master/containers.md#nn.Sequential) Module. It differs in that
it can be constructed from a list of [Models](../model/model.lua) instead of 
[Modules](https://github.com/torch/nn/blob/master/module.md#modules). Models have extra 
methods, allowing them to [accept](model.md#dp.Model.accept) 
[Visitors](visitor.md#dp.Visitor), to communicate with 
other components through a [Mediator](../mediator.lua), 
or [setup](node.md#dp.Node.setup) with variables after initialization.
Model instances also differ from Modules in their ability to [forward](model.md#dp.Model.forward) 
and [backward](model.md#dp.Model.backward) using [Views](view.md#dp.View).  

## Propagator ##
Next we initialize some [Propagators](propagator.md#dp.Propagator). 
Each such Propagator will propagate examples from a different [DataSet](data.md#dp.DataSet).
[Samplers](data.md#dp.Sampler) iterate over DataSets to 
generate [Batches](data.md#dp.Batch) of examples (inputs and targets) to propagate through the `model`:
```lua
--[[Propagators]]--
train = dp.Optimizer{
   loss = dp.NLL(),
   visitor = { -- the ordering here is important:
      dp.Momentum{momentum_factor = opt.momentum},
      dp.Learn{learning_rate = opt.learningRate},
      dp.MaxNorm{max_out_norm = opt.maxOutNorm}
   },
   feedback = dp.Confusion(),
   sampler = dp.ShuffleSampler{batch_size = opt.batchSize},
   progress = true
}
valid = dp.Evaluator{
   loss = dp.NLL(),
   feedback = dp.Confusion(),  
   sampler = dp.Sampler{}
}
test = dp.Evaluator{
   loss = dp.NLL(),
   feedback = dp.Confusion(),
   sampler = dp.Sampler{}
}
```
For this example, we use an [Optimizer](../propagator/optimizer.lua) for the training DataSet,
and two [Evaluators](../propagator/evaluator.lua), one for cross-validation 
and another for testing. 

### Sampler ###
The Evaluators use a simple Sampler which 
iterates sequentially through the DataSet. On the other hand, the Optimizer 
uses a [ShuffleSampler](data.md#dp.SuffleSampler) to iterate through the DataSet. This Sampler
shuffles the (indices of a) DataSet before each epoch (an epoch is usually defined as an iteration 
over a DataSet). This shuffling is useful for training since the model 
must learn from varying sequences of batches at each epoch, which makes the
training algorithm more stochastic.

### Loss ###
Each Propagator must also specify a [Loss](loss.md#dp.Loss) for training or evaluation.
If you have previously used the [nn](https://github.com/torch/nn/blob/master/README.md) package, 
there is nothing new here, a [Loss](loss/loss.lua) is simply an adapter of
[Criterions](https://github.com/torch/nn/blob/master/criterion.md#nn.Criterion). 
Each example has a single target class and our Model output is LogSoftMax so 
we use a [NLL](loss.md#dp.NLL), which wraps a 
[ClassNLLCriterion](https://github.com/torch/nn/blob/master/criterion.md#nn.ClassNLLCriterion).

### Feedback ###
The `feedback` parameter is used to provide us with, you guessed it, feedback; like performance measures and
statistics after each epoch. We use [Confusion](feedback.md#dp.Confusion), which is a wrapper 
for the [optim](https://github.com/torch/optim/blob/master/README.md) package's 
[ConfusionMatrix](https://github.com/torch/optim/blob/master/ConfusionMatrix.lua).
While our Loss measures the Negative Log-Likelihood (NLL) of the Model 
on different DataSets, our Feedback measures classification accuracy (which is what 
we will use for early-stopping and comparing our model to the state of the art).

### Visitor ###
Since the [Optimizer](propagator.md#dp.Optimizer) is used to train the Model on a DataSet, 
we need to specify some Visitors to update its [parameters](model.md#dp.Model.parameters). 
We want to update the Model by sequentially appling three visitors: 
 1. [Momentum](../visitor/momentum.lua) : updates parameter gradients using a factored mixture of current and previous gradients.
 2. [Learn](../visitor/learn.lua) : updates the parameters using the gradients and a learning rate.
 3. [MaxNorm](../visitor/maxnorm.lua) : updates output or input neuron weights (in this case, output) so that they have a norm less or equal to a specified value.

The only mandatory Visitor is the second one (Learn), which does the actual parameter updates (learning). 
The first is the well known momentum. 
The last is the lesser known hard constraint on the norm of output or input neuron weights 
(see [Hinton 2012](http://arxiv.org/pdf/1207.0580v1.pdf)), which acts as a regularizer. You could also
replace it with a more classic regularizer like [WeightDecay](../visitor/weightdecay.lua), in which case you 
would have to put it *before* the Learn visitor.

Finally, we have the Optimizer switch on its `progress` bar so we 
can monitor its progress during training. 

## Experiment ##
Now its time to put this all togetherto form an [Experiment](../propagator/experiment.lua):
```lua
--[[Experiment]]--
xp = dp.Experiment{
   model = model,
   optimizer = train,
   validator = valid,
   tester = test,
   observer = {
      dp.FileLogger(),
      dp.EarlyStopper{
         error_report = {'validator','feedback','confusion','accuracy'},
         maximize = true,
         max_epochs = opt.maxTries
      }
   },
   random_seed = os.time(),
   max_epoch = opt.maxEpoch
}
```
### Observer ###
The Experiment can be initialized with a list of [Observers](../observer/observer.lua). The 
order is not important. Observers listen to mediator [Channels](mediator.lua). The Mediator 
calls them back when certain events occur. In particular, they may listen to the _doneEpoch_
Channel to receive a report from the Experiment after each epoch. A report is nothing more than 
a hierarchy of tables. After each epoch, the component objects of the Experiment (except Observers) 
can submit a report to its composite parent thereby forming a tree of reports. The Observers can analyse 
these and modify the component which they are assigned to (in this case, Experiment). 
Observers may be attached to Experiments, Propagators, Visitors, etc. 

#### FileLogger ####
Here we use a simple [FileLogger](../observer/filelogger.lua) which will 
store serialized reports in a simple text file for later use. Each experiment has a unique ID which are 
included in reports, thus allowing the FileLogger to name its file appropriately. 

#### EarlyStopper ####
The [EarlyStopper](../observer/earlystopper.lua) is used for stopping the Experiment when error has not decreased, or accuracy has not 
be maximized. It also saves onto disk the best version of the Experiment when it finds a new one. 
It is initialized with a channel to `maximize` or minimize (default is to minimize). In this case, we intend 
to early-stop the experiment on a field of the report, in particular the _accuracy_ field of the 
_confusion_ table of the _feedback_ table of the `validator`. 
This `{'validator','feedback','confusion','accuracy'}` happens to measure the accuracy of the Model on the 
validation DataSet after each training epoch. So by early-stopping on this measure, we hope to find a 
Model that generalizes well. The parameter `max_epochs` indicates how much consecutive 
epochs of training can occur without finding a new best model before the experiment is signaled to stop 
on the _doneExperiment_ Mediator Channel.

## Running the Experiment ##
Once we have initialized the experiment, we need only run it on the `datasource` to begin training.
```lua
xp:run(datasource)
```
We don't initialize the Experiment with the DataSource so that we may easily 
save it onto disk, thereby keeping this snapshot separate from its data 
(which shouldn't be modified by the experiment).

Let's run the [script](../examples/neuralnetwork_tutorial.lua) from the cmd-line:
```
nicholas@xps:~/projects/dp$ th examples/neuralnetwork_tutorial.lua 
checking for file located at: 	/home/nicholas/data/mnist/mnist-th7.tgz	
checking for file located at: 	/home/nicholas/data/mnist/mnist-th7.tgz	
checking for file located at: 	/home/nicholas/data/mnist/mnist-th7.tgz	
FileLogger: log will be written to /home/nicholas/save/xps:25044:1398320864:1/log	
xps:25044:1398320864:1:optimizer:loss avgError 0	
xps:25044:1398320864:1:validator:loss avgError 0	
xps:25044:1398320864:1:tester:loss avgError 0	
==> epoch # 1 for optimizer	
 [================================ 50000/50000 ===============================>] ETA: 0ms | Step: 0ms                              

==> epoch size = 50000 examples	
==> batch duration = 0.10882427692413 ms	
==> epoch duration = 5.4412138462067 s	
==> example speed = 9189.1260687829 examples/s	
==> batch speed = 71.790047412366 batches/s	
xps:25044:1398320864:1:optimizer:loss avgError 0.0037200363330228	
xps:25044:1398320864:1:validator:loss avgError 0.004545687570244	
xps:25044:1398320864:1:tester:loss avgError 0.0047699521407681	
xps:25044:1398320864:1:optimizer:confusion accuracy = 0.88723958333333	
xps:25044:1398320864:1:validator:confusion accuracy = 0.92788461538462	
xps:25044:1398320864:1:tester:confusion accuracy = 0.92027243589744	
==> epoch # 2 for optimizer	
 [================================ 50000/50000 ===============================>] ETA: 0ms | Step: 0ms                              

==> epoch size = 50000 examples	
==> batch duration = 0.10537392139435 ms	
==> epoch duration = 5.2686960697174 s	
==> example speed = 9490.0141018538 examples/s	
==> batch speed = 74.140735170733 batches/s	
xps:25044:1398320864:1:optimizer:loss avgError 0.0023303674656008	
xps:25044:1398320864:1:validator:loss avgError 0.0044356466501897	
xps:25044:1398320864:1:tester:loss avgError 0.0046304688698266	
xps:25044:1398320864:1:optimizer:confusion accuracy = 0.92375801282051	
xps:25044:1398320864:1:validator:confusion accuracy = 0.93129006410256	
xps:25044:1398320864:1:tester:confusion accuracy = 0.92548076923077	
==> epoch # 3 for optimizer	
 [===============................ 10112/50000 ................................] ETA: 8s540ms | Step: 0ms  
```

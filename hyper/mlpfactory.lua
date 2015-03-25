------------------------------------------------------------------------
--[[ MLPFactory ]]--
-- An example experiment builder for training Mnist using an 
-- MLP of arbitrary dept
------------------------------------------------------------------------
local MLPFactory, parent = torch.class("dp.MLPFactory", "dp.ExperimentFactory")
MLPFactory.isMLPFactory = true
   
function MLPFactory:__init(config)
   config = config or {}
   local args, name, logger, save_strategy = xlua.unpack(
      {config},
      'MLPFactory', nil,
      {arg='name', type='string', default='MLP'},
      {arg='logger', type='dp.Logger', 
       help='defaults to dp.FileLogger'},
      {arg='save_strategy', type='object', 
       help='defaults to dp.SaveToFile()'}
   )
   config.name = name
   self._save_strategy = save_strategy or dp.SaveToFile()
   parent.__init(self, config)
   self._logger = logger or dp.FileLogger()
end

function MLPFactory:buildTransfer(activation)
   return nn[activation]()
end

function MLPFactory:buildDropout(dropout_prob)
   if dropout_prob and dropout_prob > 0 and dropout_prob < 1 then
      return nn.Dropout(dropout_prob)
   end
end

function MLPFactory:addInput(mlp, activation, input_size, opt)
   print(input_size .. " input neurons")
   return input_size
end

function MLPFactory:addHidden(mlp, activation, input_size, layer_index, opt)
   layer_index = layer_index or 1
   local output_size = math.ceil(
      opt.model_width * opt.width_scales[layer_index]
   )
   mlp:add(
      dp.Neural{
         input_size=input_size, output_size=output_size,
         transfer=self:buildTransfer(activation), 
         dropout=self:buildDropout(opt.dropout_probs[layer_index]),
         acc_update=opt.acc_update
      }
   )
   print(output_size .. " hidden neurons")
   if layer_index < (opt.model_dept-1) then
      return self:addHidden(mlp, activation, output_size, layer_index+1, opt)
   else
      return output_size
   end
end

function MLPFactory:addOutput(mlp, input_size, opt)
   mlp:add(
      dp.Neural{
         input_size=input_size, output_size=opt.nClasses,
         transfer=nn.LogSoftMax(), 
         dropout=self:buildDropout(opt.dropout_probs[#(opt.dropout_probs)]),
         acc_update=opt.acc_update
      }
   )
   print(opt.nClasses.." output neurons")
end

function MLPFactory:buildModel(opt)
   --[[Model]]--
   local mlp = dp.Sequential()
   -- input layer
   local input_size = self:addInput(mlp, opt.activation, opt.feature_size, opt)
   -- hidden layer(s)
   local last_size = self:addHidden(mlp, opt.activation, input_size, 1, opt)
   -- output layer
   self:addOutput(mlp, last_size, opt)
   --[[GPU or CPU]]--
   if opt.model_type == 'cuda' then
      require 'cutorch'
      require 'cunn'
      mlp:cuda()
   elseif opt.model_type == 'double' then
      mlp:double()
   elseif opt.model_type == 'float' then
      mlp:float()
   end
   print(mlp)
   return mlp
end

function MLPFactory:buildLearningRateSchedule(opt)
   --[[ Schedules ]]--
   local start_lr = opt.learning_rate
   local schedule
   if opt.linear_decay then
      x = torch.range(1,opt.decay_points[#opt.decay_points])
      y = torch.FloatTensor(x:size()):fill(start_lr)
      for i = 2, #opt.decay_points do
         local start_epoch = opt.decay_points[i-1]
         local end_epoch = opt.decay_points[i]
         local end_lr = start_lr * opt.decay_factor
         local m = (end_lr - start_lr) / (end_epoch - start_epoch)
         y[{{start_epoch,end_epoch}}] = torch.mul(
            torch.add(x[{{start_epoch,end_epoch}}], -start_epoch), m
         ):add(start_lr)
         start_lr = end_lr
      end
      schedule = y
   else
      schedule = {}
      for i, epoch in ipairs(opt.decay_points) do
         start_lr = start_lr * opt.decay_factor
         schedule[epoch] = start_lr
      end
   end
   return dp.LearningRateSchedule{schedule=schedule}
end

function MLPFactory:buildVisitor(opt)
   --[[ Visitor ]]--
   local visitor = {}
   if opt.momentum and opt.momentum > 0 then
      if opt.acc_update then
         print"Warning : momentum is ignored with acc_update = true"
      end
      table.insert(visitor, 
         dp.Momentum{
            momentum_factor = opt.momentum, 
            nesterov = opt.nesterov
         }
      )
   end
   if opt.weight_decay and opt.weight_decay > 0 then
      if opt.acc_update then
         print"Warning : weightdecay is ignored with acc_update = true"
      end
      table.insert(visitor, dp.WeightDecay{wd_factor=opt.weight_decay})
   end
   table.insert(visitor, 
      dp.Learn{
         learning_rate = opt.learning_rate, 
         observer = self:buildLearningRateSchedule(opt)
      }
   )
   if opt.max_out_norm and opt.max_out_norm > 0 then
      table.insert(visitor, 
         dp.MaxNorm{
            max_out_norm = opt.max_out_norm,
            period = opt.max_norm_period
         }
      )
   end
   return visitor
end

function MLPFactory:buildOptimizer(opt)
   local visitor = self:buildVisitor(opt)
   --[[Propagators]]--
   return dp.Optimizer{
      loss = dp.NLL(),
      visitor = visitor,
      feedback = dp.Confusion(),
      sampler = dp.ShuffleSampler{
         batch_size=opt.batch_size, sample_type=opt.model_type
      },
      progress = opt.progress
   }
end

function MLPFactory:buildValidator(opt)
   return dp.Evaluator{
      loss = dp.NLL(),
      feedback = dp.Confusion(),  
      sampler = dp.Sampler{batch_size=1024, sample_type=opt.model_type}
   }
end

function MLPFactory:buildTester(opt)
   return dp.Evaluator{
      loss = dp.NLL(),
      feedback = dp.Confusion(),
      sampler = dp.Sampler{batch_size=1024, sample_type=opt.model_type}
   }
end

function MLPFactory:buildObserver(opt)
   return {
      self._logger,
      dp.EarlyStopper{
         start_epoch = 11,
         error_report = {'validator','feedback','confusion','accuracy'},
         maximize = true,
         max_epochs = opt.max_tries,
         save_strategy = self._save_strategy,
         min_epoch = 10, max_error = opt.max_error or 0.1
      }
   }
end

function MLPFactory:build(opt, id)
   --[[Experiment]]--
   return dp.Experiment{
      id = id,
      random_seed = opt.random_seed,
      model = self:buildModel(opt),
      optimizer = self:buildOptimizer(opt),
      validator = self:buildValidator(opt),
      tester = self:buildTester(opt),
      observer = self:buildObserver(opt),
      max_epoch = opt.max_epoch
   }
end

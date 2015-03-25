------------------------------------------------------------------------
--[[ dp.Container ]]--
-- Composite of Model Components
------------------------------------------------------------------------
local Container, parent = torch.class("dp.Container", "dp.Model")
Container.isContainer = true

function Container:__init(config)
   assert(type(config) == 'table', "Constructor requires key-value arguments")
   config = config or {}
   local args, models = xlua.unpack(
      {config},
      'Container', 
      'Composite of Model Components',
      {arg='models', type='table', help='a table of models'}
   )
   self._models = {}      
   parent.__init(self, config)
   if models then
      self:extend(models)
   end
end

function Container:extend(models)
   for model_idx, model in pairs(models) do
      self:add(model)
   end
end

function Container:add(model)
   assert(not self._setup, 
      "Should insert models before calling setup()!")
   table.insert(self._models, model)
end

function Container:size()
   return #self._models
end

function Container:get(index)
   return self._models[index]
end

function Container:inputType(input_type)
   error"Not Implemented"
end

function Container:outputType(output_type)
   error"Not Implemented"
end

function Container:_type(type)
   -- find submodels in classic containers 'models'
   if not _.isEmpty(self._models) then
      for i, model in ipairs(self._models) do
         model:type(type)
      end
   end
end

function Container:_accept(visitor)
   for i=1,#self._models do 
      self._models[i]:accept(visitor)
   end 
   visitor:visitContainer(self)
end

function Container:report()
   -- merge reports
   local report = {typename=self._typename}
   for k, model in ipairs(self._models) do
      report[model:name()] = model:report()
   end
   return report
end

function Container:doneBatch(...)
   for i=1,#self._models do
      self._models[i]:doneBatch(...)
   end
   self.backwarded = false
   parent.doneBatch(self, ...)
end

function Container:zeroGradParameters()
   for i=1,#self._models do
      self._models[i]:zeroGradParameters()
   end
end

function Container:reset(stdv)
   for i=1,#self._models do
      self._models[i]:reset(stdv)
   end
end

function Container:parameters()
   local params = {}
   local gradParams = {}
   local scales = {}
   local idx = 0
   for i=1,#self._models do
      local param, gradParam, scale, size = self._models[i]:parameters()
      local n = 0
      if param then
         for k,p in pairs(param) do
            params[idx+k] = p
            if gradParam then
               gradParams[idx+k] = gradParam[k]
            end
            if scale then
               scales[idx+k] = scale[k] 
            end
            n = n + 1
         end
      end
      idx = idx + (size or n)
   end
   return params, gradParams, scales, idx
end

function Container:_toModule()
   error"Not Implemented"
end

function Container:verbose(verbose)
   self._verbose = (verbose == nil) and true or verbose
   for k, v in pairs(self._models) do
      v:verbose(self._verbose)
   end
end

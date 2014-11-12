-------------------------------------------------
--[[ Svhn ]]--
-- http://ufldl.stanford.edu/housenumbers
-- A color-image set of 10 digits.
-------------------------------------------------
local Svhn, DataSource = torch.class("dp.Svhn", "dp.DataSource")
Svhn.isSvhn = true

Svhn._name = 'svhn'
Svhn._image_size = {3, 32, 32}
Svhn._feature_size = 3*32*32
Svhn._image_axes = 'bchw'
Svhn._classes = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}

function Svhn:__init(config)
   config = config or {}
   assert(torch.type(config) == 'table' and not config[1],
      "Constructor requires key-value arguments")
   local load_all, input_preprocess, target_preprocess

   self.args, self._valid_ratio, self._train_file, self._test_file,
   self._data_path, self._shuffle, self._scale, self._download_url, 
   load_all, input_preprocess, target_preprocess
      = xlua.unpack(
      {config},
      'Svhn', 
      'Street View House Numbers datasource',
      {arg='valid_ratio', type='number', default=1/6,
        help='proportion of training set to use for cross-validation.'},
      {arg='train_file', type='string', default='train_32x32.t7',
       help='name of train_file'},
      {arg='test_file', type='string', default='test_32x32.t7',
       help='name of test_file'},
      {arg='data_path', type='string', default=dp.DATA_DIR,
        help='path to data repository'},
      {arg='shuffle', type='boolean',
        help='shuffle different sets', default=false},
      {arg='scale', type='table', default=false,
        help='bounds to scale the values between'},
      {arg='download_url', type='string',
        default='https://stife076.files.wordpress.com/2014/09/svhn.zip',
        help='URL from which to download dataset if not found on disk.'},
      {arg='load_all', type='boolean',
        help='Load all datasets : train, valid, test.', default=true},
      {arg='input_preprocess', type='table | dp.Preprocess',
        help='to be performed on set inputs, measuring statistics ' ..
        '(fitting) on the train_set only, and reusing these to ' ..
        'preprocess the valid_set and test_set.'},
      {arg='target_preprocess', type='table | dp.Preprocess',
        help='to be performed on set targets, measuring statistics ' ..
        '(fitting) on the train_set only, and reusing these to ' ..
        'preprocess the valid_set and test_set.'}
   )
   if (self._scale == nil) then
      self._scale = {0,1}
   end
   if load_all then
      self:loadTrainValid()
      self:loadTest()
   end
   DataSource.__init(self, {train_set=self:trainSet(),
                        valid_set=self:validSet(),
                        test_set=self:testSet(),
                        input_preprocess=input_preprocess,
                        target_preprocess=target_preprocess})
end

function Svhn:loadTrainValid()
   local inputs, targets = self:loadData(
      self._train_file, self._download_url
   )
   
   -- train
   local start = 1
   local size = math.floor(inputs:size(1)*(1-self._valid_ratio))
   self:setTrainSet(
      self:createDataSet(
         inputs:narrow(1, start, size),
         targets:narrow(1, start, size),
         'train'
      )
   )
   
   -- valid
   start = size + 1
   size = inputs:size(1) - start
   self:setValidSet(
      self:createDataSet(
         inputs:narrow(1, start, size),
         targets:narrow(1, start, size),
         'valid'
      )
   )

   return self:trainSet(), self:validSet()
end

function Svhn:loadTest()
   local inputs, targets = self:loadData(
      self._test_file, self._download_url
   )
   self:setTestSet(self:createDataSet(inputs, targets, 'test'))
   return self:testSet()
end

--Creates an Svhn Dataset out of data and which_set
function Svhn:createDataSet(inputs, targets, which_set)
   if self._shuffle then
      local indices = torch.randperm(inputs:size(1)):long()
      local inputs = inputs:index(1, indices)
      local targets = targets:index(1, indices)
   end

   if self._scale then
      DataSource.rescale(inputs, self._scale[1], self._scale[2])
   end

   -- construct inputs and targets dp.Views
   local input_v, target_v = dp.ImageView(), dp.ClassView()
   input_v:forward(self._image_axes, inputs)
   target_v:forward('b', targets)
   target_v:setClasses(self._classes)

   -- construct dataset
   return dp.DataSet{inputs=input_v,targets=target_v,which_set=which_set}
end

function Svhn:loadData(file_name, download_url)
   local doc_path = DataSource.getDataPath{
      name=self._name, url=download_url,
      decompress_file=file_name, data_dir=self._data_path
   }
   local fin = torch.DiskFile(doc_path)
   local tbl = fin:readObject()
   tbl.y = tbl.y:resize(tbl.y:size(2))
   return tbl.X:type('torch.DoubleTensor'), tbl.y
end

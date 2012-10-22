to = require('action-base').routeTo
c = require '../app/controllers'

module.exports = (app) ->
  app.get '/', to c.HomeController, 'index'
  app.options '/upload', to c.UploadController, 'options'
  app.post '/upload', to c.UploadController, 'upload'


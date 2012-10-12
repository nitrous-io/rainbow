to = require '../app/lib/route_to'
c = require '../app/controllers'

module.exports = (app) ->
  app.get '/', to c.HomeController, 'index'
  app.post '/upload', to c.UploadController, 'upload'


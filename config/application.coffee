express = require 'express'

module.exports = (app) ->
  app.configure ->
    app.enable 'trust proxy'
    app.use express.cookieParser()
    app.use express.bodyParser()
    app.use express.limit('20mb')
    app.use express.methodOverride()


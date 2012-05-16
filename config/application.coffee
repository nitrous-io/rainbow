express = require 'express'

module.exports = (app) ->
  app.configure ->
    app.use express.cookieParser()
    app.use express.bodyParser()
    app.use express.methodOverride()


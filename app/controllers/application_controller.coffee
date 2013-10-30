BaseController = require('action-base').BaseController

module.exports = class ApplicationController extends BaseController
  _addNoCacheHeaders: ->
    @response.set 'Pragma', 'no-cache'
    @response.set 'Cache-Control', 'no-store, no-cache, must-revalidate'

  _addCORSHeaders: ->
    settings = @app.settings
    @response.set 'Access-Control-Allow-Origin',  settings.corsAllowedOrigin
    @response.set 'Access-Control-Allow-Methods', settings.corsAllowedMethods
    @response.set 'Access-Control-Allow-Headers', settings.corsAllowedHeaders
    @response.set 'Access-Control-Allow-Credentials', true

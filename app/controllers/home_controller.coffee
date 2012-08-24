ApplicationController = require './application_controller'

module.exports = class HomeController extends ApplicationController
  index: ->
    @response.send('action-box-server OK', 200)


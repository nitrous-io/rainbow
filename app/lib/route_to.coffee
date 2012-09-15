util = require 'util'
logger = require './logger'

module.exports = routeTo = (controllerClass, action) ->
  (req, res) ->
    controller = new controllerClass(req, res)
    if process.env.NODE_ENV != 'test'
      logger.info """
        Started #{req.method} \"#{req.url}\" for #{req.headers['x-forwarded-for'] || req.connection.remoteAddress} at #{new Date}
         Processing by #{controllerClass.name}##{action}
         Params: #{util.inspect controller.params}
      """
    controller[action]()


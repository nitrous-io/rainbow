util = require 'util'

module.exports = routeTo = (controllerClass, action) ->
  (req, res) ->
    controller = new controllerClass(req, res)
    if process.env.NODE_ENV != 'test'
      console.log """
        Started #{req.method} \"#{req.url}\" for #{req.headers['x-forwarded-for'] || req.connection.remoteAddress} at #{new Date}
         Processing by #{controllerClass.name}##{action}
         Params: #{util.inspect controller.params}
      """
    controller[action]()


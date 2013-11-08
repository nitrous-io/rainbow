ApplicationController = require './application_controller'
User = require '../models/user'
Box = require '../models/box'
fs = require 'fs'
Path = require 'path'

module.exports = class DownloadController extends ApplicationController
  index: ->
    this._addCORSHeaders()
    User.verifyUserSession @request.cookies._aio_session, (err, user) =>
      if err || !user
        return @response.send 401, { error: 'You need to sign in or sign up before continuing.' }

      boxId = @params['id']
      path = @params['path']

      unless boxId && path
        return @response.send 404, { error: 'Box id and path must be provided.' }

      Box.findById boxId, [], (err, box) =>
        if err
          return @response.send 403, { error: 'Invalid box id.' }

        # check if the user has access to the given box
        box.isAccessibleByUserId user.id, (err, accessible) =>
          if !accessible
            return @response.send 403, { error: "You don't have access to the given box." }

          filePath = Path.join @app.settings.downloadsDir, path

          @response.download filePath, (err) ->
            # delete the file after one download attempt,
            # whatever the outcome is.
            fs.unlinkSync filePath
            fs.rmdirSync Path.dirname(filePath)

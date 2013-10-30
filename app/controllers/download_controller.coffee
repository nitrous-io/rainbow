ApplicationController = require './application_controller'
User = require '../models/user'
Box = require '../models/box'
fs = require 'fs'
path = require 'path'

module.exports = class DownloadController extends ApplicationController
  index: ->
    this._addCORSHeaders()
    User.verifyUserSession @request.cookies._aio_session, (err, user) =>
      if err || !user
        return @response.send 401, { error: 'You need to sign in or sign up before continuing.' }

      boxId = @params["box_id"]
      token = @params["token"]

      Box.findById boxId, [], (err, box) =>
        if err
          return @response.send 403, { error: 'Invalid box id.' }

        # check if the user has access to the given box
        box.isAccessibleByUserId user.id, (err, accessible) =>
          if !accessible
            return @response.send 403, { error: "You don't have access to the given box." }

          filePath = path.join @app.settings.downloadsDir, "#{boxId}_#{token}"

          @response.download filePath, (err) ->
            # delete the file after one download attempt,
            # whatever the outcome is.
            fs.unlink filePath

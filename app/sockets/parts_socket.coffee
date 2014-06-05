_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
stringHelper = actionBase.stringHelper
app = require '../../app'

childProcess = require 'child_process'

homePath = '/home/action'
partsPath = "#{homePath}/.parts/autoparts/bin/parts"

module.exports = class PartsSocket extends RainbowSocket
  namespace: 'parts'

  initialize: ->
    this.on 'start',      _.bind(@onStart,     this)
    this.on 'listAll',    _.bind(@onListAll,   this)
    this.on 'status',     _.bind(@onStatus,    this)

    # following commands are handled with a common streaming handler.
    this.on 'install',     (part) => @_streamPartsCommand 'install', part
    this.on 'uninstall',   (part) => @_streamPartsCommand 'uninstall', part
    this.on 'partStart',   (part) => @_streamPartsCommand 'start', part
    this.on 'partStop',    (part) => @_streamPartsCommand 'stop', part

  destroy: ->
    @ssh = undefined

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      ack?()

  onListAll: (ack) ->
    command = "#{partsPath} search --json && #{partsPath} list --json"
    @ssh.execCommand command, { timeout: 60000 }, (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null

      parts = []
      installed = []

      lines = stdout.split("\n").slice(0, 2)

      if lines.length != 2
        console.log("ERR: Invalid parts command output:\n#{stdout}")
        return ack? 'invalid command output', parts

      try
        parts = JSON.parse(lines[0])
        installed = JSON.parse(lines[1])
      catch err
        console.log("ERR: Failed to parse JSON: #{err}\n#{stdout}")
        return ack? 'invalid command output', parts

      _.each parts, (part) ->
        _.extend part, { installed: false, installed_version: null }

      _.each installed, (installedPart) ->
        matchingPart = _.find(parts, (currentPart) ->
          currentPart.name == installedPart.name
        )

        return if !matchingPart
        _.extend matchingPart, { installed: true, installed_version: installedPart.versions[0] }

      return ack? null, parts

  onStatus: (ack) ->
    @ssh.execCommand "#{partsPath} status --json", { timeout: 60000 }, (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null

      try
        parts = JSON.parse(stdout)
      catch err
        console.log("ERR: Invalid JSON - #{err}")
        return ack? 'invalid command output', []

      return ack? null, parts

  _streamPartsCommand: (command, part) ->
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs.push "export LC_ALL=en_US.UTF-8;"
      sshArgs.push "#{partsPath} #{command} #{stringHelper.escape part}"

      partsProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      partsProcess.stdout.on 'data', (data) =>
        this.send 'commandOutput', data.toString()

      partsProcess.stderr.on 'data', (data) =>
        this.send 'commandError', data.toString()

      partsProcess.on 'close', (code) =>
        deleteKeyFile()
        this.send 'commandComplete', code

      partsProcess.on 'error', ->
        deleteKeyFile()

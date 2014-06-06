_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
stringHelper = actionBase.stringHelper
app = require '../../app'

childProcess = require 'child_process'

homePath = '/home/action'
partsPath = "#{homePath}/.parts/autoparts/bin/parts"

listItemRegex = ///
  ^             # start of line
  (.+)          # part name
  \s+           # followed by some spaces
  \(([^(]+)\)   # version inside brackets
  $             # end of line
///

searchItemRegex = ///
  ^             # start of line
  (.+)          # part name
  \s+           # followed by some spaces
  \(([^(]+)\)   # version inside brackets
  \s+           # followed by some spaces
  (.+)          # description
  $             # end of line
///


statusItemRegex = ///
  ^             # start of line
  ([\S]*)       # part name
  \s*           # followed by some spaces
  ([\S]*)       # status (which is a single word without spaces)
  $             # end of line
///

module.exports = class PartsSocket extends RainbowSocket
  namespace: 'parts'

  initialize: ->
    this.on 'start',      _.bind(@onStart,     this)
    this.on 'list',       _.bind(@onList,      this)
    this.on 'listAll',    _.bind(@onListAll,   this)
    this.on 'search',     _.bind(@onSearch,    this)
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

  onList: (ack) ->
    this._runPartsCommand "list", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      if stdout.match /parts: no installed package found/
        return ack? null, []
      lines = stdout.split "\n"
      lines.pop()
      parts = []
      for line in lines
        if match = line.match listItemRegex
          name = match[1]
          version = match[2]
          parts.push { name: name, version: version }
      return ack? null, parts

  onSearch: (term, ack) ->
    this._runPartsCommand "search #{stringHelper.escape term}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      lines = stdout.split "\n"
      lines.pop()
      parts = []
      for line in lines
        if match = line.match searchItemRegex
          name = match[1]
          version = match[2]
          description = match[3]
          parts.push { name: name, version: version, description: description }
      return ack? null, parts

  onStatus: (term, ack) ->
    if term?.length
      escapedTerm = stringHelper.escape term
    else
      escapedTerm = ''

    this._runPartsCommand "status #{escapedTerm}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      lines = stdout.split "\n"
      lines.pop()
      parts = []
      for line in lines
        if match = line.match statusItemRegex
          name = match[1]
          status = match[2].toLowerCase()
          parts.push { name: name, status: status }
      return ack? null, parts

  onListAll: (ack) ->
    separator = '------installedParts------'
    command = "#{partsPath} search && echo '#{separator}' && #{partsPath} list"

    if !@ssh
      console.log("WARN: Received parts.listall with no ssh connection")
      ack?('No ssh connection')
      return

    @ssh.execCommand command, (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null

      lines = stdout.split "\n"
      lines.pop()
      parts = []
      installedList = false
      for line in lines
        # installed packages list
        # starts after the separator.
        if line == separator
          installedList = true

        unless installedList
          if match = line.match searchItemRegex
            name = match[1]
            version = match[2]
            description = match[3]
            parts.push { name: name, version: version, description: description, installed: false, installed_version: null }
        else
          if match = line.match listItemRegex
            name = match[1]
            version = match[2]
            part = _.find parts, (p) ->
              (p.name == name)
            # For some reason within autoparts (Greg was making changes to packages within autoparts directly)
            # it was failing and this part was failing cos it was not finding a part object
            if part
              part.installed = true
              part.installed_version = version

      return ack? null, parts

  _runPartsCommand: (command, callback)->
    if !@ssh
      console.log("WARN: Received parts.#{command} with no ssh connection")
      callback('No ssh connection')
      return

    # increase the timeout for SSH exec commands.
    @ssh.execCommand "#{partsPath} #{command}", { timeout: 60000 }, callback

  _streamPartsCommand: (command, part) ->
    if !@ssh
      console.log("WARN: Received parts.#{command} with no ssh connection")
      return

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

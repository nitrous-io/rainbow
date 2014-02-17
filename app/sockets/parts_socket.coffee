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

    # following commands can be handled with a common handler.
    this.on 'install',    _.bind(@onPartsCommand, this, 'install')
    this.on 'uninstall',  _.bind(@onPartsCommand, this, 'uninstall')
    this.on 'partStart',  _.bind(@onPartsCommand, this, 'start')
    this.on 'partStop',   _.bind(@onPartsCommand, this, 'stop')

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
    command = "source #{homePath}/.bashrc && source #{homePath}/.bash_profile && #{partsPath} search && echo '#{separator}' && #{partsPath} list"
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
            part.installed = true
            part.installed_version = version

      return ack? null, parts

  onPartsCommand: (command, part, ack) ->
    this._runPartsCommand "#{command} #{stringHelper.escape part}", (err, stdout, stderr) ->
      if err
        return ack? err.toString(), null
      return ack? null, stdout

  _runPartsCommand: (command, callback)->
    # increase the timeout for SSH exec commands.
    @ssh.execCommand "source #{homePath}/.bashrc && source #{homePath}/.bash_profile && #{partsPath} #{command}", { timeout: 60000 }, callback

  _runPartsCommandWithStreaming: (command) ->
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs.push("export LC_ALL=en_US.UTF-8; #{partsPath} #{command}")

      # TODO: pass the parts path and related env variables
      partsProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      partsProcess.stdout.on 'data', (data) =>
        this.send 'output', data

      partsProcess.on 'close', (code) =>
        deleteKeyFile()
        this.send 'close', code

      partsProcess.on 'error', ->
        deleteKeyFile()

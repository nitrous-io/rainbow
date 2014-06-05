_ = require 'underscore'

BaseCommand = require './base_command'
Path =  require 'path'

homePath = '/home/action'

module.exports = class UnzipCommand extends BaseCommand
  errorSlugs:
    fileNotFound: 'FILENOTFOUND'
    extractDirNeeded: 'EXTRACTDIRNEEDED'
    cannotCreateDir: 'CANNOTCREATEDIR'

  # @file - file to extract
  # @sendFn - func(event, data) to be called for sending over socket
  constructor: (@file, @sendFn) ->
    super()
    @file = Path.resolve homePath, this._shellEscape(@file)

  extractDir: ->
    @file.replace(/.zip$|.ZIP$/, '')

  commandPath: ->
    "/usr/bin/unzip"

  commandArguments: ->
    args = [
      '-n'  # never override existing files
      '-q'  # run in quiet mode
    ]
    args.push @file                      # zip file to extract
    args.push "-d #{this.extractDir()}"  # directory to extract
    args

  detectErrors: (data) ->
    switch
      when data.match /cannot find or open/
        this.errorSlugs.fileNotFound
      when data.match /must specify directory to which to extract with -d option/
        this.errorSlugs.extractDirNeeded
      when data.match /cannot create extraction directory/
        this.errorSlugs.cannotCreateDir
      else
        null

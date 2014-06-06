_ = require 'underscore'

BaseCommand = require './base_command'
Path =  require 'path'

homePath = '/home/action'
tmpPath = '/tmp'

module.exports = class CompressCommand extends BaseCommand
  errorSlugs:
    cannotCreateOutputFile: 'CANNOT_CREATE_OUTPUT_FILE'
    noDirectoryToCompress: 'NO_DIRECTORY_TO_COMPRESS'

  # @directory - directory to extract
  # @sendFn - func(event, data) to be called for sending over socket
  constructor: (@directory, @sendFn) ->
    super()
    @directory = Path.resolve homePath, this._shellEscape(@directory)

  compressedFilePath: ->
    filepath = Path.basename(@directory)
    Path.resolve tmpPath, filepath

  commandPath: ->
    "/usr/bin/zip"

  commandArguments: ->
    args = [
      '-9'  # compress better
      '-r'  # recurse into directories
      '-q'  # run in quiet mode
    ]
    args.push  this.compressedFilePath()  # path for the zip file
    args.push @directory                  # directory to compress
    args

  detectErrors: (data) ->
    switch
      when data.match /Could not create output file/
        this.errorSlugs.cannotCreateOutputFile
      when data.match /Nothing to do!/ # error returned when an invalid directory path given
        this.errorSlugs.noDirectoryToCompress
      else
        null

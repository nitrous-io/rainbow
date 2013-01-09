Lynx = require 'lynx'
logger = require './logger'
on_error = (err) -> logger.error err.message

# Wrapper around Lynx to have prefix append to all `stat`
class Metrics extends Lynx
  constructor: (@host, @port, @prefix) -> @metrics = new Lynx @host, @port, on_error: on_error
  increment: (stat, sampleRate)        -> @metrics.increment "#{@prefix}.#{stat}", sampleRate
  decrement: (stat, sampleRate)        -> @metrics.decrement "#{@prefix}.#{stat}", sampleRate
  timing: (stat, duration, sampleRate) -> @metrics.timing "#{@prefix}.#{stat}", duration, sampleRate
  gauge: (stat, value, sampleRate)     -> @metrics.gauge "#{@prefix}.#{stat}", value, sampleRate
  set: (stat, value, sampleRate)       -> @metrics.set "#{@prefix}.#{stat}", value, sampleRate

host = process.env.STATSD_HOST
port = process.env.STATSD_PORT
prefix = "rainbow.#{process.env.STATSD_ENV}"
module.exports = metrics = new Metrics host, port, prefix

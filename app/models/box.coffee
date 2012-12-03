BaseModel = require('action-base').BaseModel
KeyPair = require './key_pair'
pg = require('pg').native
A = require 'async'

BaseModel.createInstance = (err, res, callback) ->
  return callback err, null if err
  result = res.rows[0]
  if result
    model = new this
    model[k] = v for own k, v of result
    callback null, model
  else
    callback "#{@name} not found", null

module.exports = class Box extends BaseModel
  findKeyPair: (callback) ->
    KeyPair.findOne 'box_id = $1', [@id], callback

# find a box that user can worked on. The box can be created by the user, or
# shared to the user, in which ever cases user should belongs to `box_admins`
Box.for_user = (userId, boxId, cb) ->
  A.waterfall [
    (cb) -> pg.connect (err, client) -> cb err, client
    (client, cb) ->
      client.query "SELECT b.id, b.owner_id, b.host, b.port
	FROM boxes b INNER JOIN box_admins ba
	ON b.id = ba.box_id WHERE ba.user_id = $1 AND b.id = $2
	LIMIT 1", [userId, boxId], cb
  ], (err, res) -> Box.createInstance err, res, cb

Box.tableName = 'boxes'


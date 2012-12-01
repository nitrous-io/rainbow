# TODO: probably can be moved into action-base
_  = require 'underscore'
pg = require('pg').native

create_boxes_table = (client) ->
  client.query "CREATE TABLE IF NOT EXISTS boxes(
    id integer PRIMARY KEY DEFAULT nextval('serial'),
    name varchar(255),
    host varchar(255),
    state varchar(255),
    box_template_id integer,
    owner_id integer,
    region_id integer,
    port integer)"

create_users_table = (client) ->
  client.query "CREATE TABLE IF NOT EXISTS users(
    id integer PRIMARY KEY DEFAULT nextval('serial'),
    username varchar(255),
    email varchar(255))"

create_box_admins_table = (client) ->
  client.query "CREATE TABLE IF NOT EXISTS box_admins(
    id integer PRIMARY KEY DEFAULT nextval('serial'),
    box_id integer,
    user_id integer)"

create_key_pairs_table = (client) ->
  client.query "CREATE TABLE IF NOT EXISTS key_pairs(
    id integer PRIMARY KEY DEFAULT nextval('serial'),
    box_id integer
    public_key varchar(255)
    encrypted_private_key varchar(255)
    encrypted_private_key_iv varchar(255))"

flush = (client) ->
  client.query "DELETE from boxes"
  client.query "DELETE from users"
  client.query "DELETE from box_admins"
  client.query "DELETE from key_pairs"

Fixture =
  waitTilDone: (client, done) ->
    client.on 'drain', ->
      client.end()
      done()

  setup: (done) ->
    client = new pg.Client()
    client.connect()
    create_boxes_table client
    create_users_table client
    create_box_admins_table client
    @waitTilDone client, done

  flush: (done) ->
    client = new pg.Client()
    client.connect()
    flush client
    @waitTilDone client, done

  insert: (table, attributes, cb) ->
    placeholder = []
    keys = _.keys(attributes).concat ["created_at", "updated_at"]
    values = _.values(attributes).concat([new Date(), new Date()])
    _.each values, (_, index) -> placeholder.push "$#{index + 1}"

    insert = "INSERT INTO #{table}( #{keys.join(",")} )
      VALUES( #{placeholder.join(",")} ) RETURNING id"

    pg.connect (err, client) ->
      client.query insert, values, (err, res) -> cb null, res.rows[0].id

  box: (attributes, cb) ->
    default_attr = { name: "test", owner_id: 1, host: "192.168.0.1" }
    _.extend attributes, default_attr
    @insert "boxes", attributes, cb

  key_pair: (attributes, cb) ->
    default_attr =
      public_key: "public-key"
      encrypted_private_key: "encrypted_private_key"
      encrypted_private_key_iv: "iv"
    _.extend attributes, default_attr
    @insert "key_pairs", attributes, cb

module.exports = Fixture

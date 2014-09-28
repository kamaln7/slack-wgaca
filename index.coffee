config = require './config.coffee'

r = require 'rethinkdb'
rdbConn =
r.connect config.rethinkdb, (err, conn) ->
	if err?
		console.log "RethinkDB Error: #{err}"
		process.exit 1
	else
		rdbConn = conn

	db = config.rethinkdb.db
	r.db(db).tableCreate('karma').run rdbConn, (err, result) ->
		throw err if err? and err.name isnt 'RqlRuntimeError'
	
	express = require 'express'
	app = express()
	bodyParser = require 'body-parser'
	app.use bodyParser.urlencoded extended: true
	app.use bodyParser.json()
	
	router = express.Router()
	
	router.post '/hubot/slack-webhook', (req, res) ->
		console.log req.body
	
	app.use router
	
	app.listen config.express.port, config.express.host, ->
		console.log "Express listening on #{config.express.host}:#{config.express.port}"
	
	Slack = require 'node-slack'

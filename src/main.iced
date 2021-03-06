
minimist = require 'minimist'
CSON = require 'cson'
fs = require 'fs'
{make_esc} = require 'iced-error'
JSON5 = require 'json5'
{drain} = require 'iced-utils'
{Forge} = require './forge'
{TeamForge} = require './teamforge'
ics = require 'iced-coffee-script'
path = require 'path'

#===================================================

# Reads and parses a data file.
exports.Chain = class Chain

  #------------------------

  constructor : ({@file, @fh, @format, @outfh, @dir}) ->
    @_raw = null
    @_dat = null

  #------------------------

  load : ({}, cb) ->
    esc = make_esc cb, "load"
    await @_read esc defer @_raw
    await @_parse @_raw, esc defer @_dat
    cb null, @_dat

  #------------------------

  # Get the data from the file.
  get_data : () -> @_dat

  #------------------------

  _read : (cb) ->
    esc = make_esc cb, "_read"
    if @fh?
      await drain.drain @fh, esc defer dat
    else
      await fs.readFile @file, esc defer dat
      @_guess_format @file
    cb null, dat

  #------------------------

  _guess_format : () ->
    if (m = @file.match /^(.*)\.([^.]*)$/)
      @stem = path.basename m[1]
      @dir or= (path.dirname(m[1]) or '.')
      @format = m[2] unless @format

  #------------------------

  _parse : (raw, cb) ->
    err = obj = null
    try
      switch (f = @format?.toLowerCase())
        when 'json'
          obj = JSON.parse raw
        when 'cson'
          obj = CSON.parse raw
        when 'json5'
          obj = JSON5.parse raw
        when 'iced'
          obj = ics.eval raw.toString()
        else
          err = new Error "unknown format: #{f}"
    catch e
      err = e
    cb err, obj

  #------------------------

  outfile_name : () -> path.join @dir, @stem + ".json"

  #------------------------

  output : (dat, cb) ->
    if @outfh
      @outfh.write dat
    else if @stem?
      await fs.writeFile @outfile_name(), dat, defer err
    else
      err = new Error 'no output possible'
    cb err

#===================================================

exports.Runner = class Runner

  constructor : ({}) ->
    @_files = []

  parse_argv : ({argv}, cb) ->
    parsed = minimist argv, { boolean : [ "c", "check", "p", "pretty", "h", "help" ]}
    @_files = parsed._
    @format = parsed.f or parsed.format
    @team = parsed.t or parsed.team
    @check_only = parsed.c or parsed.check
    @dir = parsed.d or parsed.dir
    @pretty = parsed.p or parsed.pretty
    @help = parsed.h or parsed.help
    cb null

  run : ({argv}, cb) ->
    esc = make_esc cb, "run"
    await @parse_argv {argv}, esc defer()

    if @help
      return @show_help()

    if @_files.length
      @_chains = (new Chain { file : f, @format, @dir } for f in @_files)
    else
      @_chains = [ new Chain { fh : process.stdin, @format, outfh : process.stdout } ]

    for c in @_chains
      await c.load {}, esc defer()
      if @team
        f = new TeamForge { chain : c.get_data() }
      else
        f = new Forge { chain : c.get_data().chain }
      await f.forge esc defer out
      out = JSON.stringify(out, null, (if @pretty then 4 else null))
      await c.output out, esc defer() unless @check_only

    cb null

  show_help : () ->
    console.log """
    Usage:
      forge-sigchain [-f <format>] [-t] [-c] [-p] <files>

      If <files> are not provided, stdin will be used.
      -f, --format   format (json, cson, iced, etc)
      -t, --team     generate a team chain
      -c, --check    check only
      -p, --pretty   pretty print output
    """

#===================================================

exports.main = () ->
  r = new Runner {}
  await r.run { argv : process.argv[2...] }, defer err
  if err?
    console.log err.toString()
    process.exit 2
  else
    process.exit 0

#===================================================

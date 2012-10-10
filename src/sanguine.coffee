#!/usr/bin/env node

fs = require('fs')
path = require('path')
util = require('util')
_ = require('underscore')
exec = require('child_process').exec
easyimg = require('easyimage')
{log, trace} = console

CONFIG = '/sanguine.json'

module.exports = class sanguine
	constructor: () ->
		@config = null
		@base = null
		@filecount = 0
		@cleanup = []

		@colorRegexp = /-(\d+)c/g
		@jpgRegexp = /-(\d+)j/g
		@retinaTagRegexp = /(-1x)|(-2x)/g
		@retinaRegexp = /-2x/g

	optimize: (@configpath) ->
		unless @configpath?
			@configpath = './'

		@_loadConfig((err) =>
			if err then return log(err)
			@_parse()
		)
		
	_loadConfig: (fn) ->
		if @configpath.indexOf(CONFIG) is -1
			@configpath += CONFIG
		@configpath = path.normalize(@configpath)

		fs.readFile(@configpath, 'utf8', (err, data) =>
			if err then return fn(new Error('Failed to load sanguine.json.'))
			try
				@config = JSON.parse(data)
			catch err
				if err then return fn(new Error('Failed to parse sanguine.json.'))
			@base = path.dirname(@configpath)
			fn()
		)

	_parse: () =>
		_.each(@config, (set)=>
			source = path.join(@base, set.source)
			target = path.join(@base, set.target)
			@_parseDirectory(source, target, set)
		)

	_parseDirectory: (source, target, set) =>
		fs.readdir(source, (err, files) =>
			_.each(files, (file, key) =>
				src = path.join(source, file)
				stats = fs.statSync(src)
				if err then log(err)
				if stats.isDirectory()
					@_parseDirectory(src, path.join(target, file), set)
				else if stats.isFile() and path.extname(src) is '.png'
					unless fs.existsSync(target)
						fs.mkdirSync(target)
					return @_parseFile(src, target, set)
			)
		)

	_parseFile: (src, target, set) =>
		@retinaRegexp.lastIndex = 0
		if @retinaRegexp.test(src)
			unretinaTarget = src.replace(@retinaRegexp, '-1x')
			@_unretinaFile(src, unretinaTarget, (err) =>
				if err then return 
				@cleanup.push(unretinaTarget)
				@_parseFile(unretinaTarget, target, set)
			)
		
		fileTarget = path.join(target, path.basename(src))
		fileTarget = fileTarget.replace(@colorRegexp, '')
		fileTarget = fileTarget.replace(@jpgRegexp, '')

		fileColors = @_getAllRegExp(@colorRegexp, src)
		fileJpg = @_getAllRegExp(@jpgRegexp, src)
		if fileColors.length is 0 and fileJpg.length is 0 
			fileColors = set.colors
			fileJpg = set.jpg

		@filecount += fileColors.length + fileJpg.length
		if fileColors.length > 0
			_.each(fileColors, (color) =>
				@_optimizeFile(src, fileTarget, color, fileColors.length > 1 || set.embelish, @_fileParsed)
			)

		if fileJpg.length > 0
			_.each(fileJpg, (quality) =>
				@_jpgFile(src, fileTarget, quality, fileJpg.length > 1 || set.embelish, @_fileParsed)
			)

	_fileParsed: (err, src, target) =>
		if err then return log(err)
		@_syncTime(src, target)
		@filecount--
		log('Created target: ' + target)
		if @filecount is 0
			@_cleanup()

	_cleanup: ()=>
		if @cleanup.length > 0
			_.each(@cleanup, (file) =>
				@_deleteFile(file, (err) =>
					
				)
			)

	_getAllRegExp: (re, str) =>
		re.lastIndex = 0
		arr = []
		while (match = re.exec(str)) 
			arr.push(parseInt(match[1]))
		arr
	
	_unretinaFile: (src, target, fn) =>
		easyimg.info(src, (err, stdout, stderr) =>
			if (err) then throw err
			tw = parseInt(stdout.width * 0.5)
			th = parseInt(stdout.height * 0.5)
			easyimg.resize({src:src, dst:target, width:tw, height:th}, (err, image) =>
				if err then return fn(err)
				@_syncTime(src, target)
				return fn(null, src, image)
				)
		)
	
	_jpgFile: (src, target, quality, embelish, fn) =>
		if embelish then target = @_createFilename(target, '-' + quality + 'j')
		target = target.replace('.png', '.jpg')

		unless @_fileIsNew(src, target)
			return fn(new Error('File is not modified and does not need sanguining.'))

		easyimg.convert({src:src, dst:target, quality:quality}, (err, stdout, stderr) =>
			if err then return fn(err)
			fn(null, src, target)
		)
	
	_optimizeFile: (src, target, colors, embelish, fn) =>
		if embelish then target = @_createFilename(target, '-' + colors + 'c')

		unless @_fileIsNew(src, target)
			return fn(new Error('File is not modified and does not need sanguining.'))

		@_duplicateFile(src, target, (err) =>
			if err then return fn(err)
			child = exec('pngquant -ext .png -force -speed 1 -verbose ' + colors + ' ' + target, (err, stdout, stderr) =>
				if err? then fn(err)
				fn(null, src, target)
			)
		)
	
	_fileIsNew: (src, target) =>
		unless fs.existsSync(target) then return true
		srcStats = fs.statSync(src)
		targetStats = fs.statSync(target)
		if srcStats.mtime.valueOf() is targetStats.mtime.valueOf()
			return false
		return true

	_syncTime: (src, target) =>
		stats = fs.statSync(src)
		fs.utimesSync(target, stats.atime, stats.mtime)

	_createFilename: (target, tag) =>
		@retinaTagRegexp.lastIndex = 0
		match = @retinaTagRegexp.exec(target)
		if match?
			type = match[0]
			target = target.replace(type, tag + type)
		else
			target = target.replace('.', tag + '.')

		target

	_duplicateFile: (src, target, fn) =>
		@_deleteFile(target, () =>
			rs = fs.createReadStream(src)
			ws = fs.createWriteStream(target)
			rs.pipe(ws)
			rs.once('end', (err) =>
				if err then fn(err)
				fn()
			)
		)
	
	_deleteFile: (target, fn) =>
		fs.exists(target, (exists) =>
			if exists
				fs.unlink(target, (err) =>
					return fn()
				)
			else 
				return fn()
		)
	

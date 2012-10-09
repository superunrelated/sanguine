#!/usr/bin/env node

fs = require('fs')
path = require('path')
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
		@unretinaRegexp = /-2x/g

	optimize: (configpath) ->
		@_loadConfig(configpath, (err) =>
			@_parse()
		)
		
	_loadConfig: (configpath, fn) ->
		if configpath.indexOf(CONFIG) is -1
			configpath += CONFIG
		configpath = path.normalize(configpath)

		fs.readFile(configpath, 'utf8', (err, data) =>
			if err then return fn(new Error('Failed to load sanguine.json.'))
			try
				@config = JSON.parse(data)
			catch err
				if err then return fn(new Error('Failed to parse sanguine.json.'))
			@configpath = configpath
			@base = path.dirname(configpath)
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
				fs.stat(src, (err, stats) =>
					if err then log(err)
					if stats.isDirectory()
						@_parseDirectory(src, path.join(target, file), set)
					else if stats.isFile() and path.extname(src) is '.png'
						fs.exists(target, (exists) =>
							if exists
								return @_parseFile(src, target, set)

							fs.mkdir(target, null, (err) =>
								if err then throw err
								return @_parseFile(src, target, set)
							)
						)
				)
			)
		)

	_parseFile: (src, target, set) =>
		if @unretinaRegexp.test(src)
			unretinaTarget = src.replace(@unretinaRegexp, '-1x')
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
		if not fileColors? and not fileJpg?
			fileColors = set.colors
			fileJpg = set.jpg

		@filecount += fileColors.length + fileJpg.length

		_.each(fileColors, (color) =>
			@_optimizeFile(src, fileTarget, color, @_fileParsed)
		)
	
		_.each(fileJpg, (quality) =>
			@_jpgFile(src, fileTarget, quality, @_fileParsed)
		)

	_fileParsed: (err, file) =>
		if err then return log(err)
		@filecount--
		log('Created file: ' + file)
		if @filecount is 0
			@_cleanup()

	_cleanup: ()=>
		_.each(@cleanup, (file) =>
			@_deleteFile(file, (err) =>
				
			)
		)

	_getAllRegExp: (re, str) =>
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
				return fn(null, image)
				)
		)
	
	_jpgFile: (src, target, quality, fn) =>
		target = target.replace('.png', '.jpg')
		target = target.replace('.', '-' + quality + 'j.')
		easyimg.convert({src:src, dst:target, quality:quality}, (err, stdout, stderr) =>
			if err then return fn(err)
			fn(null, target)
		)
	
	_optimizeFile: (src, target, colors, fn) =>
		target = target.replace('.', '-' + colors + 'c.')
		@_duplicateFile(src, target, (err) =>
			if err then return fn(err)
			child = exec('pngquant --ext .png --force --speed 1 --verbose ' + colors + ' ' + target, (err, stdout, stderr) =>
				if err? then fn(err)
				fn(null, target)
			)
		)
	
	_duplicateFile: (src, target, fn) =>
		@_deleteFile(target, () =>
			rs = fs.createReadStream(src)
			ws = fs.createWriteStream(target)
			rs.pipe(ws)
			rs.once('end', fn)
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
	

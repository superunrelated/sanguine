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
		@base = null
		@images = []
		@filecount = 0
		@existCount = 0
		@cleanup = []

		@colorRegexp = /-(\d+)c/g
		@jpgRegexp = /-(\d+)j/g
		@retinaTagRegexp = /(-1x)|(-2x)/g
		@retinaRegexp = /-2x/g

	optimize: (@configpath) ->
		unless @configpath
			@configpath = './'
		if @configpath.indexOf(CONFIG) is -1
			@configpath = path.join(@configpath + CONFIG)
		@configpath = path.normalize(@configpath)
		@base = path.dirname(@configpath)

		log("@configpath", @configpath)

		@_loadJSON(@configpath, (err, config) =>
			if err then return log(err)
			@_parseConfig(config)
		)
		
	_loadJSON: (path, fn) ->
		fs.readFile(path, 'utf8', (err, data) =>
			if err then return fn(new Error('Failed to load sanguine.json.'))
			try
				data = JSON.parse(data)
			catch err
				if err then return fn(new Error('Failed to parse sanguine.json.'))
			fn(null, data)
		)

	_parseConfig: (config) =>
		_.each(config, (set)=>
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
					@images.push(
						src: src
						target: target
						set: set
					)
			)

			@_generate()
			#@_cleanup()
		)

	_generate: () =>
		_.each(@images, (image) =>	
			@_parseFile(image.src, image.target, image.set)
		)

		log(@existCount, 'files in set allready existed and was ignored.')

	_parseFile: (src, target, set) =>
		unless fs.existsSync(target)
			fs.mkdirSync(target)

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

		if fileColors.length > 0
			_.each(fileColors, (color) =>
				@_optimizeFile(src, fileTarget, color, fileColors.length > 1 || set.embelish, @_fileParsed)
			)

		if fileJpg.length > 0
			_.each(fileJpg, (quality) =>
				@_jpgFile(src, fileTarget, quality, fileJpg.length > 1 || set.embelish, @_fileParsed)
			)

	_fileParsed: (err, src, target) =>
		if err then return #log(err)
		log('Created: ' + target)

	_cleanup: ()=>
		if @cleanup.length > 0
			_.each(@cleanup, (file) =>
				@_deleteFile(file)
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
				return fn(null, src, image)
				)
		)
	
	_jpgFile: (src, target, quality, embelish, fn) =>
		if embelish then target = @_createFilename(target, '-' + quality + 'j')
		target = target.replace('.png', '.jpg')

		if fs.existsSync(target)
			@existCount++
			return fn(new Error('File exists:', target))

		easyimg.convert({src:src, dst:target, quality:quality}, (err, stdout, stderr) =>
			if err then return fn(err)
			fn(null, src, target)
		)
	
	_optimizeFile: (src, target, colors, embelish, fn) =>
		if embelish then target = @_createFilename(target, '-' + colors + 'c')

		if fs.existsSync(target)
			@existCount++
			return fn(new Error('File exists:', target))

		@_duplicateFile(src, target, (err) =>
			if err then return fn(err)
			child = exec('pngquant -ext .png -force -speed 1 -verbose ' + colors + ' ' + target, (err, stdout, stderr) =>
				if err? then fn(err)
				fn(null, src, target)
			)
		)

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
		@_deleteFile(target)
		rs = fs.createReadStream(src)
		ws = fs.createWriteStream(target)
		if rs and ws
			rs.pipe(ws)
			rs.once('error', (err) =>
				fn(err)
			)
			rs.once('end', (err) =>
				if err then fn(err)
				fn()
			)
	
	_deleteFile: (target) =>
		if fs.existsSync(target)
			fs.unlinkSync(target)

	

#!/usr/bin/env node

fs = require('fs-extra')
path = require('path')
util = require('util')
_ = require('underscore')
exec = require('child_process').exec
imagemagick = require('imagemagick')
{log, trace} = console

CONFIG = '/package.json'
OUTPUT = '/sanguine_report.json'

TYPE_JPG = 'j'
TYPE_COLOR = 'c'

module.exports = class sanguine
	constructor: () ->
		@base = null
		@images = []
		@filecount = 0
		@existCount = 0
		@cleanup = []

		@colorRegexp = /(?:-|@|^)(\d+)c/g
		@jpgRegexp = /(?:-|@|^)(\d+)j/g
		@retinaTagsRegexp = /(?:-|@|^)(?:(1x)|(2x))/g
		@retinaRegexp = /(?:-|@|^)2x/g

	optimize: (@configpath, @report, @force, @logtoconsole) ->
		@configpath
		unless @configpath
			@configpath = './'
		if @configpath.indexOf(CONFIG) is -1
			@configpath = path.join(@configpath + CONFIG)
		@configpath = path.normalize(@configpath)
		@base = path.dirname(@configpath)

		log("@configpath: ", @configpath)

		@_loadJSON(@configpath, (err, config) =>
			if err then return log(err)
			@_parseConfig(config)
			@_generate()
		)

	_loadJSON: (path, fn) ->
		fs.readFile(path, 'utf8', (err, data) =>
			if err then return fn(new Error('Failed to load:' + CONFIG))
			try
				data = JSON.parse(data)
			catch err
				if err then return fn(new Error('Failed to parse:' + CONFIG))
			fn(null, data.sanguine)
		)

	_parseConfig: (config) =>
		_.each(config, (set)=>
			source = path.join(@base, set.source)
			target = path.join(@base, set.target)
			@_parseDirectory(source, target, set)
		)

	_parseDirectory: (source, target, set) =>
		files = fs.readdirSync(source)
		_.each(files, (file, key) =>
			src = path.join(source, file)
			stats = fs.statSync(src)
			if stats.isDirectory()
				@_parseDirectory(src, path.join(target, file), set)
			else if stats.isFile() and path.extname(src) is '.png'
				srcName = path.basename(src)
				
				colors = @_getAllRegExp(@colorRegexp, srcName)
				if colors.length is 0 
					colors = set.colors
				if colors
					@_addFiles(colors, TYPE_COLOR, src, target, set.appendQuality)

				jpgs = @_getAllRegExp(@jpgRegexp, srcName)
				if jpgs.length is 0
					jpgs = set.jpgs
				if jpgs
					@_addFiles(jpgs, TYPE_JPG, src, target, set.appendQuality)
		)

	_addFiles: (versions, type, src, target, appendQuality) =>
		if versions
			unless util.isArray(versions)
				versions = [versions]

			unless fs.existsSync(target)
				fs.mkdirsSync(target)

			_.each(versions, (quality) =>
				tag = ''
				if versions.length > 1 || appendQuality
					tag = '-' + quality + type
				tgt = @_getTargetName(src, target, tag)
				if type is TYPE_JPG
					tgt = tgt.replace('.png', '.jpg')
				@images.push(
					src: src
					target: tgt
					scale: '100%'
					quality: quality
					type: type
				)
				# unretina:
				@retinaRegexp.lastIndex = 0
				if @retinaRegexp.test(path.basename(src))
					tgt = path.join(path.dirname(tgt), path.basename(tgt).replace(@retinaTagsRegexp, '$11x'))
					@images.push(
						src: src
						target: tgt
						scale: '50%'
						quality: quality
						type: type
					)
			)

	_getAllRegExp: (re, str) =>
		re.lastIndex = 0
		versions = []
		while (match = re.exec(str))
			versions.push(parseInt(match[1]))
		versions

	_getTargetName: (src, target, tag) =>
		name = path.basename(src)
		name = name.replace(@colorRegexp, '')
		name = name.replace(@jpgRegexp, '')

		if tag?
			@retinaTagsRegexp.lastIndex = 0
			match = @retinaTagsRegexp.exec(name)
			if match?
				type = match[0]
				name = name.replace(type, tag + type)
			else
				name = name.replace('.', tag + '.')

		path.join(target, name)

	# GENERATION:

	_generate: () =>
		@index = -1
		@_generateNextFile()

	_generateNextFile: (err) =>
		if err then return log(err)

		@index++
		if @index < @images.length
			@_generateFile(@images[@index], @_generateNextFile)
		else
			@_generateComplete()

	_generateComplete: () =>
		if @report
			reportPath = path.join(@base, OUTPUT)
			if fs.existsSync(reportPath)
				fs.unlinkSync(reportPath)
			fs.writeFileSync(reportPath, JSON.stringify(@images, null, 4))
			log(JSON.stringify(@images, null, 2))
			console.log('Output saved to ' + reportPath + '.')

	_generateFile: (image, fn) =>
		if fs.existsSync(image.target)
			unless @force
				image.status = 'File exists. Use -f to force recreation.' 
				if @logtoconsole
					log(image.target, image.status)
				return fn(null)
			fs.unlinkSync(image.target)

		targetDir = path.dirname(image.target)
		unless fs.existsSync(targetDir)
			fs.mkdirSync(targetDir)

		params = [image.src, '-resize', image.scale]
		if image.type is TYPE_JPG
			params.push('-quality', image.quality)
		params.push(image.target)
		imagemagick.convert(params, (err, stdout) =>
			if err
				return log(err)

			if err then fn(err)
			if image.type is TYPE_COLOR
				@_optimizeFile(image, fn)
			else
				image.status = 'Created and optimized file. ' + ('[FORCED]' if @force)
				if @logtoconsole
					log(image.target, image.status)
				fn(null)
		)

	_optimizeFile: (image, fn) =>
		child = exec('pngquant -ext .png -force -speed 1 -verbose ' + image.quality + ' ' + image.target, (err, stdout, stderr) =>
			if err? then fn(err)
			image.status = 'Created and optimized file.' + ('[FORCED]' if @force)
			if @logtoconsole
					log(image.target, image.status)
			fn(null)
		)



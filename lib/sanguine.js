var CONFIG, easyimg, exec, fs, log, path, sanguine, trace, util, _,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

fs = require('fs');

path = require('path');

util = require('util');

_ = require('underscore');

exec = require('child_process').exec;

easyimg = require('easyimage');

log = console.log, trace = console.trace;

CONFIG = '/sanguine.json';

module.exports = sanguine = (function() {

  function sanguine() {
    this._deleteFile = __bind(this._deleteFile, this);

    this._duplicateFile = __bind(this._duplicateFile, this);

    this._createFilename = __bind(this._createFilename, this);

    this._syncTime = __bind(this._syncTime, this);

    this._fileIsNew = __bind(this._fileIsNew, this);

    this._optimizeFile = __bind(this._optimizeFile, this);

    this._jpgFile = __bind(this._jpgFile, this);

    this._unretinaFile = __bind(this._unretinaFile, this);

    this._getAllRegExp = __bind(this._getAllRegExp, this);

    this._cleanup = __bind(this._cleanup, this);

    this._fileParsed = __bind(this._fileParsed, this);

    this._parseFile = __bind(this._parseFile, this);

    this._parseDirectory = __bind(this._parseDirectory, this);

    this._parse = __bind(this._parse, this);
    this.config = null;
    this.base = null;
    this.filecount = 0;
    this.cleanup = [];
    this.colorRegexp = /-(\d+)c/g;
    this.jpgRegexp = /-(\d+)j/g;
    this.retinaTagRegexp = /(-1x)|(-2x)/g;
    this.retinaRegexp = /-2x/g;
  }

  sanguine.prototype.optimize = function(configpath) {
    var _this = this;
    this.configpath = configpath;
    if (this.configpath == null) {
      this.configpath = './';
    }
    return this._loadConfig(function(err) {
      if (err) {
        return log(err);
      }
      return _this._parse();
    });
  };

  sanguine.prototype._loadConfig = function(fn) {
    var _this = this;
    if (this.configpath.indexOf(CONFIG) === -1) {
      this.configpath += CONFIG;
    }
    this.configpath = path.normalize(this.configpath);
    return fs.readFile(this.configpath, 'utf8', function(err, data) {
      if (err) {
        return fn(new Error('Failed to load sanguine.json.'));
      }
      try {
        _this.config = JSON.parse(data);
      } catch (err) {
        if (err) {
          return fn(new Error('Failed to parse sanguine.json.'));
        }
      }
      _this.base = path.dirname(_this.configpath);
      return fn();
    });
  };

  sanguine.prototype._parse = function() {
    var _this = this;
    return _.each(this.config, function(set) {
      var source, target;
      source = path.join(_this.base, set.source);
      target = path.join(_this.base, set.target);
      return _this._parseDirectory(source, target, set);
    });
  };

  sanguine.prototype._parseDirectory = function(source, target, set) {
    var _this = this;
    return fs.readdir(source, function(err, files) {
      return _.each(files, function(file, key) {
        var src, stats;
        src = path.join(source, file);
        stats = fs.statSync(src);
        if (err) {
          log(err);
        }
        if (stats.isDirectory()) {
          return _this._parseDirectory(src, path.join(target, file), set);
        } else if (stats.isFile() && path.extname(src) === '.png') {
          if (!fs.existsSync(target)) {
            fs.mkdirSync(target);
          }
          return _this._parseFile(src, target, set);
        }
      });
    });
  };

  sanguine.prototype._parseFile = function(src, target, set) {
    var fileColors, fileJpg, fileTarget, unretinaTarget,
      _this = this;
    this.retinaRegexp.lastIndex = 0;
    if (this.retinaRegexp.test(src)) {
      unretinaTarget = src.replace(this.retinaRegexp, '-1x');
      this._unretinaFile(src, unretinaTarget, function(err) {
        if (err) {
          return;
        }
        _this.cleanup.push(unretinaTarget);
        return _this._parseFile(unretinaTarget, target, set);
      });
    }
    fileTarget = path.join(target, path.basename(src));
    fileTarget = fileTarget.replace(this.colorRegexp, '');
    fileTarget = fileTarget.replace(this.jpgRegexp, '');
    fileColors = this._getAllRegExp(this.colorRegexp, src);
    fileJpg = this._getAllRegExp(this.jpgRegexp, src);
    if (fileColors.length === 0 && fileJpg.length === 0) {
      fileColors = set.colors;
      fileJpg = set.jpg;
    }
    this.filecount += fileColors.length + fileJpg.length;
    if (fileColors.length > 0) {
      _.each(fileColors, function(color) {
        return _this._optimizeFile(src, fileTarget, color, fileColors.length > 1 || set.embelish, _this._fileParsed);
      });
    }
    if (fileJpg.length > 0) {
      return _.each(fileJpg, function(quality) {
        return _this._jpgFile(src, fileTarget, quality, fileJpg.length > 1 || set.embelish, _this._fileParsed);
      });
    }
  };

  sanguine.prototype._fileParsed = function(err, src, target) {
    if (err) {
      return log(err);
    }
    this._syncTime(src, target);
    this.filecount--;
    log('Created target: ' + target);
    if (this.filecount === 0) {
      return this._cleanup();
    }
  };

  sanguine.prototype._cleanup = function() {
    var _this = this;
    if (this.cleanup.length > 0) {
      return _.each(this.cleanup, function(file) {
        return _this._deleteFile(file, function(err) {});
      });
    }
  };

  sanguine.prototype._getAllRegExp = function(re, str) {
    var arr, match;
    re.lastIndex = 0;
    arr = [];
    while ((match = re.exec(str))) {
      arr.push(parseInt(match[1]));
    }
    return arr;
  };

  sanguine.prototype._unretinaFile = function(src, target, fn) {
    var _this = this;
    return easyimg.info(src, function(err, stdout, stderr) {
      var th, tw;
      if (err) {
        throw err;
      }
      tw = parseInt(stdout.width * 0.5);
      th = parseInt(stdout.height * 0.5);
      return easyimg.resize({
        src: src,
        dst: target,
        width: tw,
        height: th
      }, function(err, image) {
        if (err) {
          return fn(err);
        }
        _this._syncTime(src, target);
        return fn(null, src, image);
      });
    });
  };

  sanguine.prototype._jpgFile = function(src, target, quality, embelish, fn) {
    var _this = this;
    if (embelish) {
      target = this._createFilename(target, '-' + quality + 'j');
    }
    target = target.replace('.png', '.jpg');
    if (!this._fileIsNew(src, target)) {
      return fn(new Error('File is not modified and does not need sanguining.'));
    }
    return easyimg.convert({
      src: src,
      dst: target,
      quality: quality
    }, function(err, stdout, stderr) {
      if (err) {
        return fn(err);
      }
      return fn(null, src, target);
    });
  };

  sanguine.prototype._optimizeFile = function(src, target, colors, embelish, fn) {
    var _this = this;
    if (embelish) {
      target = this._createFilename(target, '-' + colors + 'c');
    }
    if (!this._fileIsNew(src, target)) {
      return fn(new Error('File is not modified and does not need sanguining.'));
    }
    return this._duplicateFile(src, target, function(err) {
      var child;
      if (err) {
        return fn(err);
      }
      return child = exec('pngquant --ext .png --force --speed 1 --verbose ' + colors + ' ' + target, function(err, stdout, stderr) {
        if (err != null) {
          fn(err);
        }
        return fn(null, src, target);
      });
    });
  };

  sanguine.prototype._fileIsNew = function(src, target) {
    var srcStats, targetStats;
    if (!fs.existsSync(target)) {
      return true;
    }
    srcStats = fs.statSync(src);
    targetStats = fs.statSync(target);
    if (srcStats.mtime.valueOf() === targetStats.mtime.valueOf()) {
      return false;
    }
    return true;
  };

  sanguine.prototype._syncTime = function(src, target) {
    var stats;
    stats = fs.statSync(src);
    return fs.utimesSync(target, stats.atime, stats.mtime);
  };

  sanguine.prototype._createFilename = function(target, tag) {
    var match, type;
    this.retinaTagRegexp.lastIndex = 0;
    match = this.retinaTagRegexp.exec(target);
    if (match != null) {
      type = match[0];
      target = target.replace(type, tag + type);
    } else {
      target = target.replace('.', tag + '.');
    }
    return target;
  };

  sanguine.prototype._duplicateFile = function(src, target, fn) {
    var _this = this;
    return this._deleteFile(target, function() {
      var rs, ws;
      rs = fs.createReadStream(src);
      ws = fs.createWriteStream(target);
      rs.pipe(ws);
      return rs.once('end', function(err) {
        if (err) {
          fn(err);
        }
        return fn();
      });
    });
  };

  sanguine.prototype._deleteFile = function(target, fn) {
    var _this = this;
    return fs.exists(target, function(exists) {
      if (exists) {
        return fs.unlink(target, function(err) {
          return fn();
        });
      } else {
        return fn();
      }
    });
  };

  return sanguine;

})();

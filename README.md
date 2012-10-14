# Sanguine

An image build system for creating optimized png's, jpg's for normal and retina screens. Fast.

## Installation

Install imagemagick
```bash
$ brew install imagemagick
```

Install pngquant
```url
http://www.libpng.org/pub/png/apps/pngquant.html
```

Then
```bash
$ npm -g install sanguine
```

## Use
```bash
$ sanguine path/to/my/project -r
```
File and folder structure of the source folder will be replicated to the target folder. Files tagged in with jpg or color marker will be optimized according to the tags and copied to the target folder. Files with no tags will be optimized according to the default jpg and color settings in sanguine.json.

Examples:
- Images tagged "-x2" will be scaled down 50% and named "-1x".
- Images tagged "-16c" will be redused to 16 color png.
- Images tagged "-60j" will be compressed to a 60% quality jpg.
- Images with multiple tags like "gradient-60j-128c-2x.png" result in six files, all with different color/quality settings and image sizes.'

### Configuration
Add a sanguine.json file to your project. Build sources and targets are defined in a "sanguine.json" config file that should be located in the root of your project directory.

```json
[
  {
    "source" : "source_folder/",
    "target" : "target_folder/",
    "colors" : [64],
    "jpg" : [60],
    "appendQuality" : false
  }
]
```
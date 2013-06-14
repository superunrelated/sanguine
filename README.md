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
$ sanguine [options] path/to/my/project

Options:

-h, --help    output usage information
-r, --report  save a report file to project folder
-f, --force   forced recreation of all files
-l, --log     logs progress during creation
```

File and folder structure of the source folder will be replicated to the target folder. Files tagged in with jpg or color marker will be optimized according to the tags and copied to the target folder. Files with no tags will be optimized according to the default jpg and color settings in sanguine.json.

Examples:
- Source images named "@x2" will be scaled down 50% and named "@1x".
- Source images named "@16c" will be redused to 16 color png.
- Source images named "@60j" will be compressed to a 60% quality jpg.
- Images with multiple tags like "gradient@60j@128c@2x.png" result in six files, all with different color/quality settings and image sizes.'

### Configuration
Add a sanguine node to the package.json file of your project. 

```json
{
	"sanguine": [
		{
			"source" : "source/",
			"target" : "target/",
			"colors" : [128, 64, 32, 8],
			"jpgs" : [60, 50, 40, 10],
			"appendQuality" : true
		}
	]
}
```
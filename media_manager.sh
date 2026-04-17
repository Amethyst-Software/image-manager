#!/bin/bash

# Media Manager
# Allowing you to recursively search a directory for images and videos, you can narrow your search to only
# media of certain dimensions, a certain suffix or media type, or a certain aspect ratio. You can print the
# resulting file names to screen, label files with their dimensions, convert the files to a new format, crop
# them, flip them, rotate them and scale them. Videos can also be trimmed and sped up/down. You can replace
# the original files with your changed versions, save the altered versions beside the originals, or save them
# in a mirrored directory. Call script without arguments for usage details.
# Requires ImageMagick (for images) and FFmpeg (for videos).
# Recommended width:
# |---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -----|

IFS="
"

## CONSTANTS ##
BIN_IDENTIFY="identify"
BIN_CONVERT="convert"
BIN_FFMPEG="ffmpeg"
BIN_FFPROBE="ffprobe"
declare -a IMG_SUFF=(bmp dds jpeg jpg png tga tif tiff)
declare -a MOV_SUFF=(avi gif mov mp4 aac aif aiff flac m4a mp3 ogg opus wav wma)
declare -a AUD_SUFF=(aac aif aiff flac m4a mp3 ogg opus wav wma)
COLS=$(tput cols)
BOLD=$(tput bold)
UNDR=$(tput smul)
NORM=$(tput sgr0)
FILE_OVERWRITE=1
FILE_BESIDE=2
FILE_MIRROR=3
CROP_WIDTH_ONLY=1
CROP_HEIGHT_ONLY=2
CROP_WIDTH_HEIGHT=3
CROP_ALIGN_H_LEFT=1
CROP_ALIGN_H_CENTER=2
CROP_ALIGN_H_RIGHT=3
CROP_ALIGN_V_TOP=1
CROP_ALIGN_V_CENTER=2
CROP_ALIGN_V_BOTTOM=3
FLIP_HORI=1
FLIP_VERT=2
FLIP_BOTH=3
SCALE_WIDTH_ONLY=1
SCALE_HEIGHT_ONLY=2
SCALE_WIDTH_HEIGHT=3
SCALE_PERCENT=4
SCALE_MULTIPLY=5
SCALE_DIVIDE=6
SPEED_UP=1
SPEED_DOWN=2
CHANGE_NONE=0
CHANGE_LABEL_ONLY=1
CHANGE_MODIFY=2

## SETTINGS VARIABLES ##
FILE_MODE=0 # can be set to one of the FILE_* constants above
SOURCE_DIR=""
SOURCE_FILE=""
SHOW_SKIPS=0 # boolean
COPY_SKIPS=0 # boolean
FILTER_NAME=""
FILTER_SUFFIX=""
FILTER_TYPE=""
FILTER_WIDTH=0 # boolean
FILTER_WIDTH_PX=0
FILTER_WIDTH_OP=""
FILTER_WIDTH_OP_NAME=""
FILTER_HEIGHT=0 # boolean
FILTER_HEIGHT_PX=0
FILTER_HEIGHT_OP=""
FILTER_HEIGHT_OP_NAME=""
FILTER_ORIENT=0 # boolean
FILTER_ORIENT_TYPE=""
FILTER_RATIO=0 # boolean
FILTER_RATIO_W=0 # integer
FILTER_RATIO_H=0 # integer
FILTER_RATIO_COMPUTED=0 # floating-point number
FILTER_RATIO_FUZZ_PERC=1 # percent as a floating-point number from 0-100
FILTER_RATIO_FUZZ=0 # floating-point number
CROP_WIDTH=0
CROP_HEIGHT=0
CROP_OFFSET_X=0
CROP_OFFSET_Y=0
CROP_ALIGN_H=$CROP_ALIGN_H_LEFT # set to one of the CROP_ALIGN_H_* constants above
CROP_ALIGN_V=$CROP_ALIGN_V_TOP # set to one of the CROP_ALIGN_V_* constants above
CROP_TYPE=0 # can be set to one of the CROP_* constants above
FLIP_TYPE=0 # can be set to one of the FLIP_* constants above
ROTATE_DEG=0
SCALE_WIDTH=0
SCALE_HEIGHT=0
SCALE_PERC=0
SCALE_MULT=0
SCALE_DIV=0
SCALE_TYPE=0 # can be set to one of the SCALE_* constants above
SPEED_TYPE=0 # can be set to one of the SPEED_* constants above
TRIM_FROM="" # time format HH:MM:SS or MM:SS or S
TRIM_TO="" # time format HH:MM:SS or MM:SS or S
SPEED_DIV=0
SPEED_MULT=0
DEST_DIR=""
OPER_SEARCH=0 # boolean; only set to true if no operations below are selected by user
OPER_LABEL=0 # all booleans from here down until CHANGE_TYPE
OPER_CONVERT=0
OPER_CROP=0
OPER_FLIP=0
OPER_ROTATE=0
OPER_SCALE=0
OPER_TRIM=0
OPER_SPEED=0
CHANGE_TYPE=0 # can be set to one of the CHANGE_* constants above
NEW_SUFF=""
DRY_RUN=0 # boolean
PLAIN=0 # boolean

## SUPPORTING FUNCTIONS ##
# Trim a string before or after a separator, returning the remainder. Syntax is "trim string [before/after]
# [first/last] separator", where separator can be a single character or a string. If the user does something
# wrong, which includes supplying a separator that doesn't exist in the string, an empty string will be
# returned along with an error code.
function trim()
{
   if [ "$#" -lt 4 ]; then
      echo ""
      echo "trim(): Not enough arguments!" > /dev/stderr
      return 1
   fi

   # If the separator doesn't exist in the string, return nothing
   WITH=$(echo $1 | wc -c)
   WITHOUT=$(echo ${1%%$4*} | wc -c)
   if [ $WITH -eq $WITHOUT ]; then
      echo ""
      echo "trim(): Separator '$4' not found in '$1'!" > /dev/stderr
      return 2
   fi

   if [ $2 == "before" ]; then
      if [ $3 == "first" ]; then
         echo ${1%%$4*}
      elif [ $3 == "last" ]; then
         echo ${1%$4*}
      else
         echo ""
         echo "trim(): Expected 'first' or 'last' after 'before'!" > /dev/stderr
         return 3
      fi
   elif [ $2 == "after" ]; then
      if [ $3 == "first" ]; then
         echo ${1#*$4}
      elif [ $3 == "last" ]; then
         echo ${1##*$4}
      else
         echo ""
         echo "trim(): Expected 'first' or 'last' after 'after'!" > /dev/stderr
         return 4
      fi
   else
      echo ""
      echo "trim(): Expected 'before' or 'after', got '$2'!" > /dev/stderr
      return 5
   fi
}

# Tests if the first argument passed in is a number. The second argument is required and tells the function
# which type of number it must be: uint (positive integer), sint (any ± integer), uflt (positive integer or
# decimal number), or sflt/any (a ± integer/decimal number).
function testNum()
{
   if [ $# -ne 2 ]; then
      echo "fail"
   fi

   THE_TEST=""
   if [ $2 == "uint" ]; then
      THE_TEST="^[0-9]*$"
   elif [ $2 == "sint" ]; then
      THE_TEST="^-{0,1}[0-9]*$"
   elif [ $2 == "uflt" ]; then
      THE_TEST="^[0-9]+\.{0,1}[0-9]*$"
   elif [ $2 == "sflt" ] || [ $2 == "any" ]; then
      THE_TEST="^-{0,1}[0-9]+\.{0,1}[0-9]*$"
   fi
   
   if [[ "$1" =~ $THE_TEST ]]; then
      echo "pass"
   else
      echo "fail"
   fi
}

# Round a floating point number to an integer
function round()
{
   if [ $(testNum $1 any) == "fail" ]; then
      echo "NaN"
      return
   fi

   if [[ "$1" =~ ^-.*$ ]]; then
      echo $1 | awk '{printf "%d",int($1 - 0.5)}'
   else # positive number
      echo $1 | awk '{printf "%d",int($1 + 0.5)}'
   fi
}

# For word-wrapped output
function mypr()
{
   echo $1 | fmt -w $COLS
}

# For bold word-wrapped output
function myprb()
{
   echo -e "${BOLD}$1${NORM}" | fold -s -w $COLS
}

# For centered output
function myprc()
{
   echo $1 | fmt -w $COLS -c
}

# For debug output, toggled on by --show-skips
function myprd()
{
   if [ $SHOW_SKIPS -eq 1 ]; then
      echo $1 | fmt -w $COLS
   fi
}

# For formatted output; each line of input has underscores converted to underline markup and pipes converted
# to bold markup. For simplicity's sake, there are two assumptions: that bold and underline styling are each
# used no more than twice per line, and that each format tag is opened and closed on the same line.
function myprf()
{
   while (( "$#" )); do
      TEXT=$(echo "$1" | sed "s/_/${UNDR}/1" | sed "s/_/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/_/${UNDR}/1" | sed "s/_/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/|/${BOLD}/1" | sed "s/|/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/|/${BOLD}/1" | sed "s/|/${NORM}/1")
      echo "$TEXT"
      shift
   done
}

# Print help page for script
# 80-column margin guide for help text (but note that formatting markers below are not printed to screen):
# |----------------------------------------------------------------------------|
function printHelp()
{
   echo -n ${BOLD}
   myprc "--Media Manager Help--"
   echo -n ${NORM}
   MAN_TEXT="|You must supply one of the following arguments:|
   _--in-dir PATH_: The directory to look in recursively for image/video files.
   _--on-file FILE_: Pass the full path to a specific file to operate only on it.

|You must choose one of the following file modes if you are performing an opera-|
|tion on the media files and not just searching for them:|
   _--overwrite_ will replace each original file with the changed version.
   _--beside_ will rename the original file to '[original name]-old' and place the
      new file at the original file's location, unless you have supplied the
      argument _--label_, in which case the original file's name will remain un-
      changed.
   _--dest PATH_ will place new files in the directory _PATH_, which must already
      exist. The hierarchy of the original directory will be duplicated.
      _--copy-skips_ is a sub-option of _--dest PATH_ which tells the script to also
         copy files that were not altered. You will be able to differentiate
         these from the altered files because they will retain their original
         timestamps. If you have specified a suffix filter with the
         _--only-suffix:SUF_ argument, files that don't match the desired suffix
         will not be copied, but files that fail any other filter will be copied
         to the destination directory.

|You may utilize any or all of the following operations, or specify no operation|
|to simply print the names of all files matching your filters (if both a crop and|
|scale operation are requested, the crop will be performed first):|
   _--label_ will add the dimensions of each file to its name. If you ask for a
      label in addition to specifying some operation(s) to be performed on the
      files, the label will be applied to the new file.
   _--convert-to:SUF_ with the suffix that's associated with the file type you
      want, e.g. _--convert-to:jpg_ or _--convert-to:mp4_.
   _--crop-width:NUM_ and/or _--crop-height:NUM_ will crop the media to the desired
      width and/or height.
   _--crop-offset-x:NUM_ will offset the crop from the left side of the image or
      video by the specified number of pixels.
   Add the _--crop-align-right_ argument to make the _--crop-width:NUM_ and
      _--crop-offset-x:NUM_ arguments start from the right of the image/video
      instead of the left.
   Alternately, use _--crop-center-h_ to crop from the horizontal center. For
      example, _--crop-center-h --crop-width:101_ will crop the media down to a
      101px-wide section from its center (to be exact, 50px to the left and 51px
      to the right). In this case the _--crop-offset-x:NUM_ argument can use a
      positive or negative number to shift the crop area to the left and right
      of center.
   _--crop-offset-y:NUM_ will offset the crop from the top of the media by the
      specified number of pixels.
   Add the _--crop-align-bottom_ argument to make the _--crop-height:NUM_ and
      _--crop-offset-y:NUM_ arguments start from the bottom of the media instead
      of the top.
   Alternately, use _--crop-center-v_ to crop from the vertical center. The expla-
      nation of _--crop-center-h_ above applies here as well.
   _--flip-h_ will mirror the media around the vertical axis.
   _--flip-v_ will mirror the media around the horizontal axis.
   _--rotate:NUM_ will rotate the media by this number of degrees.
   _--scale-percent:NUM_ will scale each image or video by this percentage of its
      size, e.g. _--scale-percent:50_ will reduce the dimensions to 50%.
   _--scale-mult:NUM_ will grow the media proportionally by the given factor.
   _--scale-div:NUM_ will shrink the media proportionally by the given factor.
   _--scale-width:NUM_ and/or _--scale-height:NUM_ give the width and/or height to
      which the media should be resized. If you specify both a new width and
      height, the media will be squashed or stretched if the new proportions are
      not equal to the original proportions. If you only specify a new width or
      a new height, the scaling will take place proportionally.
   _--speed-div:NUM_ will slow down video playback by dividing the playback speed
      by the given factor (must be a value from 1.01 to 2.0) while preserving
      audio pitch. Only applies to video files.
   _--speed-mult:NUM_ will speed up video playback by multiplying the playback
      speed by the given factor (must be a value from 1.01 to 100) while
      preserving audio pitch. Only applies to video files.
   _--trim-from:TIME_ will start the trimmed output from the specified time (e.g.
      00:30:45.5 or 30:45 or 45 or 12.5). Fractional seconds are supported. This
      argument can be used alone or in combination with _--trim-to_. Only applies
      to video files.
   _--trim-to:TIME_ will end the trimmed output at the specified time (same format
      as _--trim-from_). This argument can be used alone or in combination with
      _--trim-from_. Only applies to video files.

|You may use these arguments to limit which media files will be operated upon:|
   _--only-name:RE_: Only select media files with a name body that matches the
      supplied regular expression _RE_.
   _--only-suffix:SUF_: Only select media files with the name suffix _SUF_.
   _--only-type:TYPE_: Only select one type of media. _TYPE_ must be 'image' or
      'movie'.
   Choose one of the following width arguments:
   _--only-width-eq:NUM_: Only choose media that have width _NUM_ in pixels.
   _--only-width-lt:NUM_: Only select media that have width < _NUM_ pixels.
   _--only-width-le:NUM_: Only select media that have width ≤ _NUM_ pixels.
   _--only-width-gt:NUM_: Only select media that have width > _NUM_ pixels.
   _--only-width-ge:NUM_: Only select media that have width ≥ _NUM_ pixels.
   Choose one of the following height arguments:
   _--only-height-eq:NUM_: Only select media that have height _NUM_ in pixels.
   _--only-height-lt:NUM_: Only select media that have height < _NUM_ pixels.
   _--only-height-le:NUM_: Only select media that have height ≤ _NUM_ pixels.
   _--only-height-gt:NUM_: Only select media that have height > _NUM_ pixels.
   _--only-height-ge:NUM_: Only select media that have height ≥ _NUM_ pixels.
   _--only-orient:STR_: Select media which have a certain orientation. _STR_ should
      be 'port' for portrait, 'land' for landscape, and 'square' for media of
      exactly the same height and width.
   _--only-ratio:NUM:NUM_: Select media which have a certain aspect ratio, e.g.
      _--only-ratio:16:9_.
   _--only-ratio-fuzz:NUM_: Because of slight decimal differences, some media
      may not precisely match your _--only-ratio_ argument. For instance, a
      1366x768 media is considered 16:9, but it's actually a ratio of 1.77865…
      whereas 16:9 is 1.77777…, a deviation of about 0.05%. The fuzziness is
      already set to a default of 1.0%, but you can set it higher or lower with
      this argument.

|You also have the following arguments available for troubleshooting purposes:|
   _--plain_: Prints output without styling such as bold text and fixes column
      width to 80 characters for predictable output.
   _--dry-run_: Print out the command which would be run on each file instead of
      performing the command.
   _--show-skips_: Print name of each file that was excluded by the chosen
      filters and the reason why it was excluded.
   _--custom-identify_: The name of, or complete path to, the program that should
      be used in place of 'identify'.
   _--custom-convert_: The name of, or complete path to, the program that should
      be used in place of 'convert'.
   _--custom-ffmpeg_: The name of, or complete path to, the program that should
      be used in place of 'ffmpeg'.
   _--custom-ffprobe_: The name of, or complete path to, the program that should
      be used in place of 'ffprobe'."
   myprf "$MAN_TEXT"
}

# Take apart an argument starting with "--only" and save as filter
function processOnlyArg()
{
   if [[ $1 == *name* ]]; then
      FILTER_NAME=$(trim "$1" after first :)
      if [ -z $FILTER_NAME ]; then
         mypr "Error 41: Failed to find text after '--only-name:' argument."
         exit 41
      fi
   elif [[ $1 == *suffix* ]]; then
      FILTER_SUFFIX=$(trim "$1" after first :)
      if [ -z $FILTER_SUFFIX ]; then
         mypr "Error 1: Failed to find text after '--only-suffix:' argument."
         exit 1
      fi
   elif [[ $1 == *type* ]]; then
      FILTER_TYPE=$(trim "$1" after first :)
      if [[ -z $FILTER_TYPE || ( $FILTER_TYPE != "image" && $FILTER_TYPE != "movie" ) ]]; then
         mypr "Error 39: You need to specify 'image' or 'movie' with the '--only-type:' argument."
         exit 39
      fi
   elif [[ $1 == *width* ]]; then
      FILTER_WIDTH=1
      FILTER_WIDTH_PX=$(trim "$1" after first :)
      FILTER_WIDTH_PX=$(round $FILTER_WIDTH_PX)
      if [ -z $FILTER_WIDTH_PX ] || [ $FILTER_WIDTH_PX == "NaN" ] || [ $FILTER_WIDTH_PX -lt 1 ]; then
         mypr "Error 2: Failed to parse number in '--only-width-*:NUM' argument or NUM was less than 1."
         exit 2
      fi

      FILTER_WIDTH_OP=$(trim "$1" after first "--only-width")
      FILTER_WIDTH_OP=$(trim "$FILTER_WIDTH_OP" before first :)
      if [ "$FILTER_WIDTH_OP" == "-eq" ]; then
         FILTER_WIDTH_OP_NAME=""
      elif [ "$FILTER_WIDTH_OP" == "-lt" ]; then
         FILTER_WIDTH_OP_NAME="less than "
      elif [ "$FILTER_WIDTH_OP" == "-le" ]; then
         FILTER_WIDTH_OP_NAME="less than or equal to "
      elif [ "$FILTER_WIDTH_OP" == "-gt" ]; then
         FILTER_WIDTH_OP_NAME="greater than "
      elif [ "$FILTER_WIDTH_OP" == "-ge" ]; then
         FILTER_WIDTH_OP_NAME="greater than or equal to "
      else
         mypr "Error 3: Failed to find operation 'eq', 'lt', 'le', 'gt', or 'ge' in '--only-width-*:NUM' argument."
         exit 3
      fi
   elif [[ $1 == *height* ]]; then
      FILTER_HEIGHT=1
      FILTER_HEIGHT_PX=$(trim "$1" after first :)
      FILTER_HEIGHT_PX=$(round $FILTER_HEIGHT_PX)
      if [ -z $FILTER_HEIGHT_PX ] || [ $FILTER_HEIGHT_PX == "NaN" ] || [ $FILTER_HEIGHT_PX -lt 1 ]; then
         mypr "Error 4: Failed to parse number in '--only-height-*:NUM' argument or NUM was less than 1."
         exit 4
      fi

      FILTER_HEIGHT_OP=$(trim "$1" after first "--only-height")
      FILTER_HEIGHT_OP=$(trim "$FILTER_HEIGHT_OP" before first :)
      if [ "$FILTER_HEIGHT_OP" == "-eq" ]; then
         FILTER_HEIGHT_OP_NAME=""
      elif [ "$FILTER_HEIGHT_OP" == "-lt" ]; then
         FILTER_HEIGHT_OP_NAME="less than "
      elif [ "$FILTER_HEIGHT_OP" == "-le" ]; then
         FILTER_HEIGHT_OP_NAME="less than or equal to "
      elif [ "$FILTER_HEIGHT_OP" == "-gt" ]; then
         FILTER_HEIGHT_OP_NAME="greater than "
      elif [ "$FILTER_HEIGHT_OP" == "-ge" ]; then
         FILTER_HEIGHT_OP_NAME="greater than or equal to "
      else
         mypr "Error 5: Failed to find operation 'eq', 'lt', 'le', 'gt', or 'ge' in '--only-height-*:NUM' argument."
         exit 5
      fi
   elif [[ $1 == *orient* ]]; then
      FILTER_ORIENT=1
      FILTER_ORIENT_TYPE=$(trim "$1" after first :)
      if [ $FILTER_ORIENT_TYPE != "port" ] && [ $FILTER_ORIENT_TYPE != "land" ] && [ $FILTER_ORIENT_TYPE != "square" ]; then
         mypr "Error 6: Failed to find orientation 'port', 'land' or 'square' in '--only-orient:STR' argument."
         exit 6
      fi
	elif [[ $1 == *fuzz* ]]; then
      FILTER_RATIO_FUZZ_PERC=$(trim "$1" after first :)
      FILTER_RATIO_FUZZ_PERC=$(round $FILTER_RATIO_FUZZ_PERC)
      if [ -z $FILTER_RATIO_FUZZ_PERC ] || [ $FILTER_RATIO_FUZZ_PERC == "NaN" ] || [ $FILTER_RATIO_FUZZ_PERC -lt 0 ] || [ $FILTER_RATIO_FUZZ_PERC -gt 99 ]; then
         mypr "Error 7: Failed to parse number in '--only-ratio-fuzz:NUM' argument or NUM was less than 0 or more than 99."
         exit 7
      fi

		# If we have already received the --only-ratio argument, compute final fuzz; also calculated below
		# under the "elif [[ $1 == *ratio* ]]" block in case ratio is passed in after fuzz
		if [ ! -z $FILTER_RATIO_W ]; then
			FILTER_RATIO_FUZZ=$(echo | awk -v r=$FILTER_RATIO_COMPUTED -v f=$FILTER_RATIO_FUZZ_PERC '{printf "%f",r*(f/100)}')
		fi
   elif [[ $1 == *ratio* ]]; then
      FILTER_RATIO=1
      RATIO_FULL=$(trim "$1" after first :)
      FILTER_RATIO_W=$(trim "$RATIO_FULL" before first :)
      FILTER_RATIO_W=$(round $FILTER_RATIO_W)
      if [ -z $FILTER_RATIO_W ] || [ $FILTER_RATIO_W == "NaN" ] || [ "$FILTER_RATIO_W" -lt 1 ]; then
         mypr "Error 8: Could not extract width component of aspect ratio from '--only-ratio:NUM:NUM' argument or width was less than 1."
         exit 8
      fi

      FILTER_RATIO_H=$(trim "$RATIO_FULL" after first :)
      FILTER_RATIO_H=$(round $FILTER_RATIO_H)
      if [ -z $FILTER_RATIO_H ] || [ $FILTER_RATIO_H == "NaN" ] || [ "$FILTER_RATIO_H" -lt 1 ]; then
         mypr "Error 9: Could not extract height component of aspect ratio from '--only-ratio:NUM:NUM' argument or height was less than 1."
         exit 9
      fi
      FILTER_RATIO_COMPUTED=$(echo | awk -v w=$FILTER_RATIO_W -v h=$FILTER_RATIO_H '{printf "%f",w/h}')
      # Compute how much of a margin we have; gets re-calculated above under the "elif [[ $1 == *fuzz* ]]"
      # block in case the user passes in a custom fuzz argument after the ratio
		FILTER_RATIO_FUZZ=$(echo | awk -v r=$FILTER_RATIO_COMPUTED -v f=$FILTER_RATIO_FUZZ_PERC '{printf "%f",r*(f/100)}')
   else
      mypr "Error 10: Argument '$1' began with '--only' but wasn't followed by '-suffix', '-width', '-height', '-orient', '-fuzz' or '-ratio'. Run this script without arguments for help."
      exit 10
   fi
}

# Take apart an argument starting with "--crop" and save as operation
function processCropArg()
{
   if [[ $1 == *width* ]]; then
      CROP_WIDTH=$(trim "$1" after first :)
      CROP_WIDTH=$(round $CROP_WIDTH)
      if [ -z $CROP_WIDTH ] || [ $CROP_WIDTH == "NaN" ] || [ $CROP_WIDTH -lt 1 ]; then
         mypr "Error 11: Failed to parse number in '--crop-width:NUM' argument or NUM was less than 1."
         exit 11
      fi

      if [ $CROP_TYPE -eq $CROP_HEIGHT_ONLY ]; then
         CROP_TYPE=$CROP_WIDTH_HEIGHT
      else # user did not give a height for cropping
         CROP_TYPE=$CROP_WIDTH_ONLY
      fi
   elif [[ $1 == *height* ]]; then
      CROP_HEIGHT=$(trim "$1" after first :)
      CROP_HEIGHT=$(round $CROP_HEIGHT)
      if [ -z $CROP_HEIGHT ] || [ $CROP_HEIGHT == "NaN" ] || [ $CROP_HEIGHT -lt 1 ]; then
         mypr "Error 12: Failed to parse number in '--crop-height:NUM' argument or NUM was less than 1."
         exit 12
      fi

      if [ $CROP_TYPE -eq $CROP_WIDTH_ONLY ]; then
         CROP_TYPE=$CROP_WIDTH_HEIGHT
      else # user did not give a width for cropping
         CROP_TYPE=$CROP_HEIGHT_ONLY
      fi
   elif [[ $1 == *offset-x* ]]; then
      CROP_OFFSET_X=$(trim "$1" after first :)
      CROP_OFFSET_X=$(round $CROP_OFFSET_X)
      if [ -z $CROP_OFFSET_X ] || [ $CROP_OFFSET_X == "NaN" ] || [ $CROP_OFFSET_X -eq 0 ]; then
         mypr "Error 13: Failed to parse number in '--crop-offset-x:NUM' argument or NUM was 0, which does nothing."
         exit 13
      fi
   elif [[ $1 == *offset-y* ]]; then
      CROP_OFFSET_Y=$(trim "$1" after first :)
      CROP_OFFSET_Y=$(round $CROP_OFFSET_Y)
      if [ -z $CROP_OFFSET_Y ] || [ $CROP_OFFSET_Y == "NaN" ] || [ $CROP_OFFSET_Y -eq 0 ]; then
         mypr "Error 14: Failed to parse number in '--crop-offset-y:NUM' argument or NUM was 0, which does nothing."
         exit 14
      fi
   elif [[ $1 == *align-right* ]]; then
      CROP_ALIGN_H=$CROP_ALIGN_H_RIGHT
   elif [[ $1 == *align-bottom* ]]; then
      CROP_ALIGN_V=$CROP_ALIGN_V_BOTTOM
   elif [[ $1 == *center-h* ]]; then
      CROP_ALIGN_H=$CROP_ALIGN_H_CENTER
   elif [[ $1 == *center-v* ]]; then
      CROP_ALIGN_V=$CROP_ALIGN_V_CENTER
   else
      mypr "Error 15: Argument '$1' began with '--crop' but wasn't followed by '-width', '-height' or a valid '-offset-', '-align-' or '-center' term. Run this script without arguments for help."
      exit 15
   fi
}

# Consider an argument starting with "--flip" in light of possible previous "--flip" argument
function processFlipArg()
{
   if [ "$1" == "--flip-h" ]; then
      if [ $FLIP_TYPE -eq $FLIP_VERT ]; then
         FLIP_TYPE=$FLIP_BOTH
      else
         FLIP_TYPE=$FLIP_HORI
      fi
   elif [ "$1" == "--flip-v" ]; then
      if [ $FLIP_TYPE -eq $FLIP_HORI ]; then
         FLIP_TYPE=$FLIP_BOTH
      else
         FLIP_TYPE=$FLIP_VERT
      fi
   else
      mypr "Error 33: Argument '$1' began with '--flip' but wasn't followed by '-h' or '-v'. Run this script without arguments for help."
      exit 33
   fi
}

# Set up rotation operation based on "--rotate" argument
function processRotateArg()
{
   ROTATE_DEG=$(trim "$1" after first :)
   if [ -z $ROTATE_DEG ] || [ $ROTATE_DEG -eq 0 ]; then
      mypr "Error 34: Failed to parse number in '--rotate:NUM' argument or NUM was 0, which does nothing."
      exit 34
   fi
}

# Take apart an argument starting with "--scale" and save as operation
function processScaleArg()
{
   if [[ $1 == *width* ]]; then
      SCALE_WIDTH=$(trim "$1" after first :)
      SCALE_WIDTH=$(round $SCALE_WIDTH)
      if [ -z $SCALE_WIDTH ] || [ $SCALE_WIDTH == "NaN" ] || [ $SCALE_WIDTH -lt 1 ]; then
         mypr "Error 16: Failed to parse number in '--scale-width:NUM' argument or NUM was less than 1."
         exit 16
      fi

      if [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
         SCALE_TYPE=$SCALE_WIDTH_HEIGHT
      else # user did not give a height for scaling
         SCALE_TYPE=$SCALE_WIDTH_ONLY
      fi
   elif [[ $1 == *height* ]]; then
      SCALE_HEIGHT=$(trim "$1" after first :)
      SCALE_HEIGHT=$(round $SCALE_HEIGHT)
      if [ -z $SCALE_HEIGHT ] || [ $SCALE_HEIGHT == "NaN" ] || [ $SCALE_HEIGHT -lt 1 ]; then
         mypr "Error 17: Failed to parse number in '--scale-height:NUM' argument or NUM was less than 1."
         exit 17
      fi

      if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
         SCALE_TYPE=$SCALE_WIDTH_HEIGHT
      else # user did not give a width for scaling
         SCALE_TYPE=$SCALE_HEIGHT_ONLY
      fi
   elif [[ $1 == *percent* ]]; then
      SCALE_PERC=$(trim "$1" after first :)
      SCALE_PERC=$(round $SCALE_PERC)
      if [ -z $SCALE_PERC ] || [ $SCALE_PERC == "NaN" ] || [ $SCALE_PERC -lt 1 ]; then
         mypr "Error 18: Failed to parse number in '--scale-percent:NUM' argument or NUM was less than 1."
         exit 18
      fi

      SCALE_TYPE=$SCALE_PERCENT
   elif [[ $1 == *mult* ]]; then
      SCALE_MULT=$(trim "$1" after first :)
      SCALE_MULT=$(round $SCALE_MULT)
      if [ -z $SCALE_MULT ] || [ $SCALE_MULT == "NaN" ] || [ $SCALE_MULT -lt 1 ]; then
         mypr "Error 35: Failed to parse number in '--scale-mult:NUM' argument or NUM was less than 1."
         exit 35
      fi
      SCALE_TYPE=$SCALE_MULTIPLY
   elif [[ $1 == *div* ]]; then
      SCALE_DIV=$(trim "$1" after first :)
      SCALE_DIV=$(round $SCALE_DIV)
      if [ -z $SCALE_DIV ] || [ $SCALE_DIV == "NaN" ] || [ $SCALE_DIV -lt 1 ]; then
         mypr "Error 36: Failed to parse number in '--scale-div:NUM' argument or NUM was less than 1."
         exit 36
      fi
      SCALE_TYPE=$SCALE_DIVIDE
   else
      mypr "Error 19: Argument '$1' began with '--scale' but wasn't followed by '-width', '-height', '-percent', '-mult' or '-div'. Run this script without arguments for help."
      exit 19
   fi
}

# Set up trim operation based on "--trim-from" or "--trim-to" argument
function processTrimArg()
{
   TIME_VALUE=$(trim "$1" after first :)
   if [ -z $TIME_VALUE ]; then
      mypr "Error 42: Failed to parse time value in '$1' argument."
      exit 42
   fi
   
   # Validate time format (should be HH:MM:SS.F or MM:SS.F or just seconds, with optional fractional part)
   if ! [[ $TIME_VALUE =~ ^[0-9]+(\.[0-9]+)?$|^[0-9]{1,2}:[0-9]{1,2}(\.[0-9]+)?$|^[0-9]+:[0-9]{1,2}:[0-9]{1,2}(\.[0-9]+)?$ ]]; then
      mypr "Error 43: Invalid time format in '$1'. Use format HH:MM:SS, MM:SS, or seconds (fractional seconds allowed)."
      exit 43
   fi
   
   if [[ $1 == *trim-from* ]]; then
      TRIM_FROM="$TIME_VALUE"
   elif [[ $1 == *trim-to* ]]; then
      TRIM_TO="$TIME_VALUE"
   else
      mypr "Error 44: Argument '$1' began with '--trim' but wasn't followed by '-from' or '-to'. Run this script without arguments for help."
      exit 44
   fi
}

# Take apart an argument starting with "--speed" and save as operation
function processSpeedArg()
{
   if [[ $1 == *div* ]]; then
      SPEED_DIV=$(trim "$1" after first :)
      if [ -z $SPEED_DIV ] || [ $(testNum $SPEED_DIV any) == "fail" ]; then
         mypr "Error 45: Failed to parse number in '--speed-div:NUM' argument."
         exit 45
      fi
      
      if (( $(echo "$SPEED_DIV < 1.01" | bc -l) )) || (( $(echo "$SPEED_DIV > 2.0" | bc -l) )); then
         mypr "Error 46: Speed divisor must be at least 1.01 and no more than 2.0 (this limit exists because FFmpeg's audio atempo filter cannot go below 1/2)."
         exit 46
      fi

      SPEED_TYPE=$SPEED_DOWN
   elif [[ $1 == *mult* ]]; then
      SPEED_MULT=$(trim "$1" after first :)
      if [ -z $SPEED_MULT ] || [ $(testNum $SPEED_MULT any) == "fail" ]; then
         mypr "Error 47: Failed to parse number in '--speed-mult:NUM' argument."
         exit 47
      fi
      
      if (( $(echo "$SPEED_MULT < 1.01" | bc -l) )) || (( $(echo "$SPEED_MULT > 100" | bc -l) )); then
         mypr "Error 48: Speed multiplier must be at least 1.01 and no more than 100 (this limit exists because FFmpeg's audio atempo filter cannot go higher than 100)."
         exit 48
      fi

      SPEED_TYPE=$SPEED_UP
   else
      mypr "Error 49: Argument '$1' began with '--speed' but wasn't followed by '-div' or '-mult'. Run this script without arguments for help."
      exit 49
   fi
}

# If user has supplied the --copy-skips argument, copy the file passed in even though it was not modified
function considerCopy()
{
   if [ $FILE_MODE -eq $FILE_MIRROR ] && [ $COPY_SKIPS -eq 1 ]; then
      # Create path in new dir. equivalent to path in orig. dir.
      MIRR_PATH=$(trim "$1" after first "$SOURCE_DIR/")
      MIRR_PATH=$(dirname "$MIRR_PATH")
      BASE_FILE_NAME=$(basename "$1")

      if [ "$MIRR_PATH" == "." ]; then
         MIRR_PATH=""
      else
         MIRR_PATH+="/"
      fi

      if [ $DRY_RUN -eq 0 ]; then
         if [ ! -d "$DEST_DIR/$MIRR_PATH" ]; then
            mkdir -p "$DEST_DIR/$MIRR_PATH"
         fi

         mypr "Copying unaltered file $BASE_FILE_NAME..."
         cp "$1" "$DEST_DIR/${MIRR_PATH}$BASE_FILE_NAME"
      else
         echo mkdir -p "$DEST_DIR/$MIRR_PATH"

         echo cp "$1" "$DEST_DIR/${MIRR_PATH}$BASE_FILE_NAME"
      fi
   fi
}

## CODE START ##
# The script cannot perform any action with less than three arguments, so print the documentation (this also
# covers the case where the user guesses at an argument like "--help")
if [ "$#" -lt 3 ]; then
   printHelp
   exit
fi

# Process all arguments
while (( "$#" )); do
   # Shift 2 spaces unless that takes us past the end of the argument array, which seems to hang the shell
   SAFE_2=2
   if [ "$#" -eq 1 ]; then
      SAFE_2=1
   fi

   case "$1" in
      --in-dir )          SOURCE_DIR="$2"; shift $SAFE_2;;
      --on-file )         SOURCE_FILE="$2"; shift $SAFE_2;;
      --overwrite )       FILE_MODE=$FILE_OVERWRITE; shift;;
      --beside )          FILE_MODE=$FILE_BESIDE; shift;;
      --dest )            FILE_MODE=$FILE_MIRROR; DEST_DIR="$2"; shift $SAFE_2;;
      --copy-skips )      COPY_SKIPS=1; shift;;
      --label )           OPER_LABEL=1; shift;;
      --convert-to* )     NEW_SUFF=$(trim "$1" after first :); OPER_CONVERT=1; shift;;
      --crop* )           processCropArg $1; OPER_CROP=1; shift;;
      --flip* )           processFlipArg $1; OPER_FLIP=1; shift;;
      --rotate* )         processRotateArg $1; OPER_ROTATE=1; shift;;
      --trim* )           processTrimArg $1; OPER_TRIM=1; shift;;
      --scale* )          processScaleArg $1; OPER_SCALE=1; shift;;
      --speed* )          processSpeedArg $1; OPER_SPEED=1; shift;;
      --only* )           processOnlyArg $1; shift;;
      --dry-run )         DRY_RUN=1; shift;;
      --plain )           PLAIN=1; shift;;
      --show-skips )      SHOW_SKIPS=1; shift;;
      --custom-identify ) BIN_IDENTIFY="$2"; shift $SAFE_2;;
      --custom-convert )  BIN_CONVERT="$2"; shift $SAFE_2;;
      --custom-ffmpeg )   BIN_FFMPEG="$2"; shift $SAFE_2;;
      --custom-ffprobe )  BIN_FFPROBE="$2"; shift $SAFE_2;;
      * )                 mypr "Error 21: Unrecognized argument '$1'."; exit 21;;
   esac
done

# If plain mode was requested, fix column width and strip all ANSI formatting from output functions so that
# the output is predictable regardless of terminal width or type
if [ $PLAIN -eq 1 ]; then
   COLS=80
   BOLD=""
   UNDR=""
   NORM=""
   function myprc()
   {
      printf '%s\n' "$1"
   }
fi

# Check for ImageMagick
which "$BIN_IDENTIFY" > /dev/null
if [ "$?" -ne 0 ]; then
   mypr "Error 20: '$BIN_IDENTIFY' is not available on the command line; ImageMagick does not appear to be installed."
   exit 20
fi
which "$BIN_CONVERT" > /dev/null
if [ "$?" -ne 0 ]; then
   mypr "Error 20: '$BIN_CONVERT' is not available on the command line; ImageMagick does not appear to be installed."
   exit 20
fi

# Check for FFmpeg
which "$BIN_FFMPEG" > /dev/null
if [ "$?" -ne 0 ]; then
   mypr "Error 20: '$BIN_FFMPEG' is not available on the command line; FFmpeg does not appear to be installed."
   exit 20
fi

# Set file change type accordingly
if [ $OPER_CONVERT -eq 1 ] || [ $OPER_CROP -eq 1 ] || [ $OPER_FLIP -eq 1 ] || [ $OPER_ROTATE -eq 1 ] || [ $OPER_SCALE -eq 1 ] || [ $OPER_TRIM -eq 1 ] || [ $OPER_SPEED -eq 1 ]; then
   CHANGE_TYPE=$CHANGE_MODIFY
elif [ $OPER_LABEL -eq 1 ]; then
   CHANGE_TYPE=$CHANGE_LABEL_ONLY
else # in the event of no operations, just print the file names to screen
   OPER_SEARCH=1
   CHANGE_TYPE=$CHANGE_NONE
fi

## SAFETY CHECKS ##
if [ -z $SOURCE_DIR ] && [ -z $SOURCE_FILE ]; then
   mypr "Error 22: You need to specify either a directory to search using '--in-dir PATH' or an individual file using '--on-file FULL_FILE_PATH'."
   exit 22
fi

if [ ! -z $SOURCE_FILE ] && [ ! -z $SOURCE_DIR ]; then
   mypr "Error 37: You cannot specify both a source directory and file. Use only the '--in-dir' or '--on-file' argument."
   exit 37
fi

if [ ! -z $SOURCE_DIR ] && [ ! -d "$SOURCE_DIR" ]; then
   mypr "Error 23: The directory '$SOURCE_DIR' specified with '--in-dir' does not exist."
   exit 23
fi

if [ ! -z $SOURCE_FILE ] && [ ! -f "$SOURCE_FILE" ]; then
   mypr "Error 38: The file '$SOURCE_FILE' specified with '--on-file' does not exist."
   exit 38
fi

if [ ! -z $FILTER_SUFFIX ] && [ ! -z $FILTER_TYPE ]; then
   mypr "Error 40: You cannot specify a suffix with '--only-suffix' and also a general type of media with '--only-type'."
   exit 40
fi

if [ $FILE_MODE -eq 0 ] && [ $OPER_SEARCH -eq 0 ]; then
   mypr "Error 24: Because you asked for a file operation to be performed, you need to specify the file mode with '--overwrite', '--beside', or '--dest PATH'. Run this script without arguments for help."
   exit 24
fi

if [ $FILE_MODE -eq $FILE_MIRROR ]; then
   if [ -z $DEST_DIR ]; then
      mypr "Error 25: You need to specify a destination path after the '--dest' argument."
      exit 25
   fi

   if [ ! -d "$DEST_DIR" ]; then
      mypr "Error 26: The directory '$DEST_DIR' specified with '--dest' does not exist."
      exit 26
   fi
fi

if [[ $OPER_SEARCH -eq 1 && ( $FILE_MODE -ne 0 || $COPY_SKIPS -ne 0 ) ]]; then
   mypr "Error 27: Since you only opted to print file results rather than alter any files, you should not have specified a file operation mode."
   exit 27
fi

if [ $OPER_CROP -eq 1 ] && [ $CROP_WIDTH -eq 0 ] && [ $CROP_HEIGHT -eq 0 ] && [ $CROP_OFFSET_X -eq 0 ] && [ $CROP_OFFSET_Y -eq 0 ]; then
   mypr "Error 28: You specified a crop alignment but no crop width, height or offset."
   exit 28
fi

if [[ ( $CROP_OFFSET_X -lt 0 && $CROP_ALIGN_H -ne $CROP_ALIGN_H_CENTER ) || ( $CROP_OFFSET_Y -lt 0 && $CROP_ALIGN_V -ne $CROP_ALIGN_V_CENTER ) ]]; then
   mypr "Error 29: You specified a negative crop offset but did not ask for center alignment on that axis. Negative offsets are not allowed for left- or right-aligned crop operations."
   exit 29
fi

if [[ ( $CROP_WIDTH -eq 0 && $CROP_OFFSET_X -eq 0 && $CROP_ALIGN_H -ne $CROP_ALIGN_H_LEFT ) || ( $CROP_HEIGHT -eq 0 && $CROP_OFFSET_Y -eq 0 && $CROP_ALIGN_V -ne $CROP_ALIGN_H_LEFT ) ]]; then
   mypr "Error 30: You specified a crop alignment for an axis on which you did not specify a crop size or offset."
   exit 30
fi

if [ $OPER_CONVERT -eq 1 ] && [ -z $NEW_SUFF ]; then
   mypr "Error 31: Failed to find a file suffix after '--convert-to:'."
   exit 31
fi

if [ $OPER_CONVERT -eq 1 ] && [ $FILE_MODE -ne $FILE_MIRROR ]; then
   mypr "Error 32: You can only use file-mirroring mode ('--dest PATH') with the '--convert-to' operation. Overwrite mode and beside mode would yield confusing results if they encountered a mixture of files that were already in the destination format and files that needed conversion."
   exit 32
fi

if [ $SPEED_DIV -ne 0 ] && [ $SPEED_MULT -ne 0 ]; then
   mypr "Error 50: You can't use '--speed-div' and '--speed-mult' together."
   exit 50
fi

if [ ! -z "$TRIM_FROM" ] && [ ! -z "$TRIM_TO" ] && [ $(echo "$TRIM_FROM >= $TRIM_TO" | bc -l) -eq 1 ]; then
   mypr "Error 51: The value supplied to '--trim-from' must be less than '--trim-to'."
   exit 51
fi

## SETTINGS OUTPUT ##
echo -n ${BOLD}
myprc "--Media Manager--"
echo -n ${NORM}

if [ $DRY_RUN -eq 1 ]; then
   myprb "**This is a dry run. No files will be changed.**"
fi

if [ $SHOW_SKIPS -eq 1 ]; then
   mypr "Skipped files will be noted with the reason for the skip."
fi

myprb "Filters"

ANY_FILTER=0
if [ ! -z $FILTER_NAME ]; then
   mypr "Selecting files where the body of the name matches the regex pattern '$FILTER_NAME'."
   ANY_FILTER=1
fi

if [ ! -z $FILTER_SUFFIX ]; then
   mypr "Selecting files with the suffix '$FILTER_SUFFIX'."
   ANY_FILTER=1
fi

if [ ! -z $FILTER_TYPE ]; then
   mypr "Selecting only ${FILTER_TYPE}s."
   ANY_FILTER=1
fi

if [ $FILTER_WIDTH -eq 1 ]; then
   mypr "Selecting files that are $FILTER_WIDTH_OP_NAME${FILTER_WIDTH_PX}px wide."
   ANY_FILTER=1
fi

if [ $FILTER_HEIGHT -eq 1 ]; then
   mypr "Selecting files that are $FILTER_HEIGHT_OP_NAME${FILTER_HEIGHT_PX}px tall."
   ANY_FILTER=1
fi

if [ $FILTER_ORIENT -eq 1 ]; then
   ORIENT_NAME=$FILTER_ORIENT_TYPE # "square", unless…
   if [ $FILTER_ORIENT_TYPE == "land" ]; then
      ORIENT_NAME="landscape orientation"
   elif [ $FILTER_ORIENT_TYPE == "port" ]; then
		ORIENT_NAME="portrait orientation"
	fi

   mypr "Selecting files that are $ORIENT_NAME."
   ANY_FILTER=1
fi

if [ $FILTER_RATIO -eq 1 ]; then
   mypr "Selecting files with aspect ratio ${FILTER_RATIO_W}:${FILTER_RATIO_H} (with a tolerance of ${FILTER_RATIO_FUZZ_PERC}%)."
   ANY_FILTER=1
fi

if [ $ANY_FILTER -eq 0 ]; then
   mypr "None. All media will be selected."
fi

myprb "Operations"

if [ $OPER_SEARCH -eq 1 ]; then
   mypr "The names of the selected media files will be printed to screen."
fi

if [ $OPER_CROP -eq 1 ]; then
   CROP_DIM_STMT="${CROP_WIDTH}x${CROP_HEIGHT}px"
   if [ $CROP_WIDTH -eq 0 ]; then
      if [ $CROP_HEIGHT -eq 0 ]; then
         CROP_DIM_STMT=""
      else
         CROP_DIM_STMT="${CROP_HEIGHT}px tall"
      fi
   elif [ $CROP_HEIGHT -eq 0 ]; then
      CROP_DIM_STMT="${CROP_WIDTH}px wide"
   fi

   if [ $CROP_OFFSET_X -ne 0 ] || [ $CROP_OFFSET_Y -ne 0 ]; then
      CROP_DIM_STMT+=", "

      SIDE_NAME_H="left"
      if [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_CENTER ]; then
         SIDE_NAME_H="horizontal center"
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_RIGHT ]; then
         SIDE_NAME_H="right"
      fi

      SIDE_NAME_V="top"
      if [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_CENTER ]; then
         SIDE_NAME_V="vertical center"
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_BOTTOM ]; then
         SIDE_NAME_V="bottom"
      fi

      CROP_OFFSET_STMT="offset ${CROP_OFFSET_X}x${CROP_OFFSET_Y} from the origin at ${SIDE_NAME_V}-${SIDE_NAME_H}"
   fi

   mypr "The media will be cropped to ${CROP_DIM_STMT}${CROP_OFFSET_STMT}."
fi

if [ $OPER_FLIP -eq 1 ]; then
   if [ $FLIP_TYPE -eq $FLIP_HORI ]; then
      mypr "The media will be flipped horizontally."
   elif [ $FLIP_TYPE -eq $FLIP_VERT ]; then
      mypr "The media will be flipped vertically."
   elif [ $FLIP_TYPE -eq $FLIP_BOTH ]; then
      mypr "The media will be flipped horizontally and vertically."
   fi
fi

if [ $OPER_ROTATE -eq 1 ]; then
   mypr "The media will be rotated $ROTATE_DEG degrees."
fi

if [ $OPER_SCALE -eq 1 ]; then
   if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
      mypr "The media will be proportionally scaled to make their width ${SCALE_WIDTH}px."
   elif [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
      mypr "The media will be proportionally scaled to make their height ${SCALE_HEIGHT}px."
   elif [ $SCALE_TYPE -eq $SCALE_WIDTH_HEIGHT ]; then
      mypr "The media will be non-proportionally scaled to ${SCALE_WIDTH}x${SCALE_HEIGHT}px."
   elif [ $SCALE_TYPE -eq $SCALE_PERCENT ]; then
      mypr "The media will be proportionally scaled to ${SCALE_PERC}% of their current size."
   elif [ $SCALE_TYPE -eq $SCALE_MULTIPLY ]; then
      mypr "The media will be grown proportionally by a factor of ${SCALE_MULT}x."
   elif [ $SCALE_TYPE -eq $SCALE_DIVIDE ]; then
      mypr "The media will be shrunken proportionally by a factor of ${SCALE_DIV}x."
   fi
fi

if [ $OPER_TRIM -eq 1 ]; then
   if [ $TRIM_FROM -ne 0 ]; then
      mypr "Movie files will be trimmed starting from $TRIM_FROM."
   elif [ $TRIM_TO -ne 0 ]; then
      mypr "Movie files will be trimmed to the endpoint $TRIM_TO."
   fi
fi

if [ $OPER_SPEED -eq 1 ]; then
   if [ $SPEED_TYPE -eq $SPEED_UP ]; then
      mypr "Movie files will be sped up by a factor of ${SPEED_UP}x."
   elif [ $SPEED_TYPE -eq $SPEED_DOWN ]; then
      mypr "Movie files will be slowed down by a factor of ${SPEED_DOWN}x."
   fi
fi

if [ $OPER_CONVERT -eq 1 ]; then
   FORMAT=$(echo "$NEW_SUFF" | tr "[:lower:]" "[:upper:]")
   mypr "The media will be converted from their present format to the format associated with the suffix $FORMAT."
fi

if [ $OPER_LABEL -eq 1 ]; then
   mypr "The media files will be named with their dimensions."
fi

if [ $OPER_TRIM -eq 1 ]; then
   TRIM_DISPLAY=""
   if [ ! -z "$TRIM_FROM" ]; then
      TRIM_DISPLAY="from $TRIM_FROM"
   fi
   if [ ! -z "$TRIM_TO" ]; then
      if [ ! -z "$TRIM_DISPLAY" ]; then
         TRIM_DISPLAY+=" to $TRIM_TO"
      else
         TRIM_DISPLAY="to $TRIM_TO"
      fi
   fi
   mypr "The movies will be trimmed $TRIM_DISPLAY."
fi

myprb "File Mode"

if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
   if [ ! -z $SOURCE_DIR ]; then
      mypr "The media files in $SOURCE_DIR will be altered in place."
   else
      mypr "The media file will be altered in place."
   fi
elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
   if [ ! -z $SOURCE_DIR ]; then
      mypr "The media files in $SOURCE_DIR will be altered in place after backing up the originals."
   else
      mypr "The media file will be altered in place after backing up the original."
   fi
elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
   if [ ! -z $SOURCE_DIR ]; then
      mypr "The altered media files from $SOURCE_DIR will be placed in a mirrored directory inside $DEST_DIR."
      if [ $COPY_SKIPS -eq 1 ]; then
         mypr "Unaltered files will also be copied into this mirrored directory."
      fi
   else
      mypr "The altered (or unaltered) media file will be placed in a mirrored directory."
   fi
else
   mypr "N/A"
fi

## MAIN LOOP ##
echo -------------------------------
declare -a FILE_SET=()
if [ ! -z $SOURCE_DIR ]; then
   myprb "Processing directory $SOURCE_DIR..."
   FILE_SET=($(find -s "$SOURCE_DIR" -type f))
elif [ ! -z $SOURCE_FILE ]; then
   myprb "Processing file $SOURCE_FILE..."
   FILE_SET=($SOURCE_FILE)
fi

for FILE_REF in "${FILE_SET[@]}"; do
   SRC_FILE_TYPE=""
   DST_FILE_TYPE=""

   # If this is not a file with a name and suffix, skip it
   if [[ ! "$(basename $FILE_REF)" =~ [[:print:]]+\.[[:print:]]+$ ]]; then
      myprd "Skipping file '$(basename $FILE_REF)' because it does not have both a name body and a suffix."
      continue
   fi
   
   FILE_BODY=$(trim "$FILE_REF" before last .)
   FILE_SUFFIX=$(trim "$FILE_REF" after last .)
   
   shopt -s nocasematch
   
   # Apply name body filter if requested
   if [ ! -z $FILTER_NAME ]; then
      if [[ ! "$FILTER_NAME" =~ $FILE_BODY ]]; then
         considerCopy "$FILE_REF"
         myprd "Skipping file '$(basename $FILE_REF)' because name did not pass name filter."
         continue
      fi
   fi
   
   # Apply suffix filter if requested
   if [ ! -z $FILTER_SUFFIX ]; then
      if [[ "$FILTER_SUFFIX" != $FILE_SUFFIX ]]; then
         considerCopy "$FILE_REF"
         myprd "Skipping file '$(basename $FILE_REF)' because suffix did not pass suffix filter."
         continue
      fi
   fi
   
   # Check source file's suffix against known image suffixes
   for SUFFIX in "${IMG_SUFF[@]}"; do
      if [[ "$SUFFIX" == $FILE_SUFFIX ]]; then
         SRC_FILE_TYPE="image"
         break
      fi
   done
   
   # Check source file's suffix against known movie suffixes if not identified as an image
   if [ -z $SRC_FILE_TYPE ]; then
      for SUFFIX in "${MOV_SUFF[@]}"; do
         if [[ "$SUFFIX" == $FILE_SUFFIX ]]; then
            SRC_FILE_TYPE="movie"
            break
         fi
      done
   fi
   
   # Apply type filter if requested
   if [ ! -z $FILTER_TYPE ]; then
      if [[ "$FILTER_TYPE" != $SRC_FILE_TYPE ]]; then
         considerCopy "$FILE_REF"
         myprd "Skipping file '$(basename $FILE_REF)' because type filter '$FILTER_TYPE' was requested and file is of type '$SRC_FILE_TYPE'."
         continue
      fi
   fi

   # Get file type associated with the destination suffix, if the user asked for conversion
   if [ ! -z $NEW_SUFF ]; then
      for SUFFIX in "${IMG_SUFF[@]}"; do
         if [[ "$SUFFIX" == $NEW_SUFF ]]; then
            DST_FILE_TYPE="image"
            break
         fi
      done
      if [ -z $DST_FILE_TYPE ]; then
         for SUFFIX in "${MOV_SUFF[@]}"; do
            if [[ "$SUFFIX" == $NEW_SUFF ]]; then
               DST_FILE_TYPE="movie"
               break
            fi
         done
      fi
   fi
   
   shopt -u nocasematch

   # If this is not a known type of media or the file failed to pass our filters, then don't proceed
   if [ -z $SRC_FILE_TYPE ]; then
      myprd "Skipping file '$(basename $FILE_REF)' because suffix '$SUFFIX' is not in the lists of known suffixes (see top of script)."
      continue
   fi

   # Skip images if trim operation is requested
   if [ $OPER_TRIM -eq 1 ] && [ $SRC_FILE_TYPE == "image" ]; then
      myprd "Skipping image '$(basename $FILE_REF)' because --trim only applies to movies."
      considerCopy "$FILE_REF"
      continue
   fi

   # Skip images if speed change operation is requested
   if [ $OPER_SPEED -eq 1 ] && [ $SRC_FILE_TYPE == "image" ]; then
      myprd "Skipping image '$(basename $FILE_REF)' because --speed-mult/div only applies to movies."
      considerCopy "$FILE_REF"
      continue
   fi

   # Skip images if we are converting to a movie suffix, as a one-frame movie file is not useful
   if [ "$SRC_FILE_TYPE" == "image" ] && [ "$DST_FILE_TYPE" == "movie" ]; then
      myprd "Skipping image '$(basename $FILE_REF)' because the target suffix only applies to movies."
      considerCopy "$FILE_REF"
      continue
   fi
   
   # Get media dimensions
   if [ $SRC_FILE_TYPE == "image" ]; then
      MEDIA_WIDTH=$("$BIN_IDENTIFY" -format "%[fx:w]" "$FILE_REF" 2> /dev/null)
      MEDIA_HEIGHT=$("$BIN_IDENTIFY" -format "%[fx:h]" "$FILE_REF" 2> /dev/null)
      IDENTIFY_RESULT=$?
      if [ $IDENTIFY_RESULT -ne 0 ]; then
         myprd "Skipping image '$FILE_REF' because the size could not be obtained; ImageMagick error $IDENTIFY_RESULT."
         continue
      fi
   elif [ $SRC_FILE_TYPE == "movie" ]; then
      MEDIA_DIMS=$("$BIN_FFPROBE" -v quiet -print_format csv=p=0 -show_entries stream=width,height "$FILE_REF")
      FFPROBE_RESULT=$?
      if [ $FFPROBE_RESULT -ne 0 ]; then
         myprd "Skipping movie '$FILE_REF' because the size could not be obtained; FFmpeg error $FFPROBE_RESULT."
         continue
      fi
      MEDIA_WIDTH=$(trim "$MEDIA_DIMS" before first ",")
      MEDIA_HEIGHT=$(trim "$MEDIA_DIMS" after first ",")
   fi
	
	# Animated GIFs return wildly erroneous dimensions and have not been tested with the operations this
	# script offers, so skip them
	# Update: For now I have disabled this check because I'm not sure the bug still exists, and if it does,
	# it's only for certain GIFs, so it's better to allow the operation(s) to proceed and let the user address
	# issues between ImageMagick and those specific GIFs
	#if [ $(echo $FILE_SUFFIX | tr "[:upper:]" "[:lower:]") == "gif" ]; then
	#	FRAME_CT=$("$BIN_IDENTIFY" "$FILE_REF" | wc -l | tr -d ' ')
	#	if [ $FRAME_CT -gt 1 ]; then
	#		myprd "Skipping animated GIF '$FILE_REF'."
	#		continue
	#	fi
	#fi
	
	# Avoid cases where media dimensions exceed 2^32 by filtering out dimensions over 9 digits long, because
	# bash cannot handle them; it's likely that a number this large is an error anyway
	if [ "${#MEDIA_WIDTH}" -gt 9 ] || [ "${#MEDIA_HEIGHT}" -gt 9 ]; then
	   myprd "Skipping file '$FILE_REF' because a dimension may exceed INTMAX."
	   continue
	fi

   # Apply width filter if requested
   if [ $FILTER_WIDTH -eq 1 ]; then
      if [ ! $MEDIA_WIDTH $FILTER_WIDTH_OP $FILTER_WIDTH_PX ]; then
         myprd "Skipping ${MEDIA_WIDTH}px-wide $(basename $FILE_REF) because it is not $FILTER_WIDTH_OP_NAME${FILTER_WIDTH_PX}px."
         considerCopy "$FILE_REF"
         continue
      fi
   fi

   # Apply height filter if requested
   if [ $FILTER_HEIGHT -eq 1 ]; then
      if [ ! $MEDIA_HEIGHT $FILTER_HEIGHT_OP $FILTER_HEIGHT_PX ]; then
         myprd "Skipping ${MEDIA_HEIGHT}px-tall $(basename $FILE_REF) because it is not $FILTER_HEIGHT_OP_NAME${FILTER_HEIGHT_PX}px."
         considerCopy "$FILE_REF"
         continue
      fi
   fi
   
   # Apply orientation filter if requested
   if [ $FILTER_ORIENT -eq 1 ]; then
      if [ $FILTER_ORIENT_TYPE == "port" ]; then
         if [ $MEDIA_WIDTH -gt $MEDIA_HEIGHT ]; then
            myprd "Skipping ${MEDIA_WIDTH}x${MEDIA_HEIGHT} $(basename $FILE_REF) because it is not portrait."
            considerCopy "$FILE_REF"
            continue
         fi
      elif [ $FILTER_ORIENT_TYPE == "land" ]; then
         if [ $MEDIA_WIDTH -lt $MEDIA_HEIGHT ]; then
            myprd "Skipping ${MEDIA_WIDTH}x${MEDIA_HEIGHT} $(basename $FILE_REF) because it is not landscape."
            considerCopy "$FILE_REF"
            continue
         fi
      elif [ $FILTER_ORIENT_TYPE == "square" ]; then
         if [ $MEDIA_WIDTH -ne $MEDIA_HEIGHT ]; then
            myprd "Skipping ${MEDIA_WIDTH}x${MEDIA_HEIGHT} $(basename $FILE_REF) because it is not square."
            continue
            considerCopy "$FILE_REF"
         fi
      fi
   fi

	# Apply aspect ratio filter if requested
	if [ $FILTER_RATIO -eq 1 ]; then
		IMAGE_RATIO=$(echo | awk -v w=$MEDIA_WIDTH -v h=$MEDIA_HEIGHT '{printf "%f",w/h}')

		# Get abs() of diff between media's and filter's aspect ratios
		RATIO_DIFF=$(echo $IMAGE_RATIO-$FILTER_RATIO_COMPUTED | bc)
		if [ $(echo $RATIO_DIFF'<'0 | bc -l) -eq 1 ]; then
			RATIO_DIFF=$(echo $RATIO_DIFF'*'-1 | bc -l)
		fi

		if [ $(echo $RATIO_DIFF'>'$FILTER_RATIO_FUZZ | bc -l) -eq 1 ]; then
         SOURCE_RATIO_LOW=$(echo | awk -v r=$FILTER_RATIO_COMPUTED -v f=$FILTER_RATIO_FUZZ '{printf "%f",r-f}')
         SOURCE_RATIO_HIGH=$(echo | awk -v r=$FILTER_RATIO_COMPUTED -v f=$FILTER_RATIO_FUZZ '{printf "%f",r+f}')
         myprd "Skipping ratio $IMAGE_RATIO $(basename $FILE_REF) because it is outside the range ${SOURCE_RATIO_LOW}-${SOURCE_RATIO_HIGH}."
         considerCopy "$FILE_REF"
			continue
		fi
	fi

   # If in search mode, just print file name and continue
   if [ $OPER_SEARCH -eq 1 ]; then
      REL_PATH=$(trim "$FILE_REF" after first "$SOURCE_DIR/")
      echo "Found file '$REL_PATH'."
      continue
   fi

   CROP_ARG=""
   RESIZE_ARG=""
   FLIP_ARG=""
   ROTATE_ARG=""
   TRIM_ARG_START=""
   TRIM_ARG_END=""
   SPEED_ARG=""
   IN_VF=0

   # Construct crop operation if requested
   if [ $OPER_CROP -eq 1 ]; then
      if [ $SRC_FILE_TYPE == "movie" ]; then
         CROP_ARG=" -vf \""
         IN_VF=1
      fi

      if [ $CROP_TYPE == $CROP_WIDTH_ONLY ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then CROP_ARG=" -crop ${CROP_WIDTH}x"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then CROP_ARG+="crop=$CROP_WIDTH:in_h"; fi
      elif [ $CROP_TYPE == $CROP_HEIGHT_ONLY ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then CROP_ARG=" -crop x${CROP_HEIGHT}"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then CROP_ARG+="crop=in_w:$CROP_HEIGHT"; fi
      elif [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then CROP_ARG=" -crop ${CROP_WIDTH}x${CROP_HEIGHT}"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then CROP_ARG+="crop=$CROP_WIDTH:$CROP_HEIGHT"; fi
      fi

      OFFSET_X=0
      if [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_LEFT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_X=$CROP_OFFSET_X; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then OFFSET_X=$MEDIA_WIDTH-$CROP_WIDTH; fi
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_RIGHT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_X=$(($MEDIA_WIDTH-$CROP_WIDTH-$CROP_OFFSET_X)); fi
         if [ $SRC_FILE_TYPE == "movie" ]; then OFFSET_X=$CROP_WIDTH; fi
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_CENTER ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_X=$(($MEDIA_WIDTH/2-($CROP_WIDTH/2)+$CROP_OFFSET_X)); fi
         # movie crop is already horizontally centered
      fi

      OFFSET_Y=0
      if [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_TOP ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_Y=$CROP_OFFSET_Y; fi
         # movie crop is already top-aligned
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_BOTTOM ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_Y=$(($MEDIA_HEIGHT-$CROP_HEIGHT-$CROP_OFFSET_Y)); fi
         if [ $SRC_FILE_TYPE == "movie" ]; then OFFSET_Y=$MEDIA_HEIGHT-$CROP_HEIGHT; fi
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_CENTER ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then OFFSET_Y=$(($MEDIA_HEIGHT/2-($CROP_HEIGHT/2)+$CROP_OFFSET_Y)); fi
         if [ $SRC_FILE_TYPE == "movie" ]; then OFFSET_Y=$(($MEDIA_HEIGHT/2-($CROP_HEIGHT/2))); fi
      fi

      if [ $SRC_FILE_TYPE == "image" ]; then CROP_ARG+="+${OFFSET_X}+${OFFSET_Y}"; fi
      if [ $SRC_FILE_TYPE == "movie" ]; then CROP_ARG+=":${OFFSET_X}:${OFFSET_Y}"; fi
   fi

   # Construct scale operation if requested
   if [ $OPER_SCALE -eq 1 ]; then
      if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG=" -resize"; fi
      if [ $SRC_FILE_TYPE == "movie" ]; then
         if [ $IN_VF -eq 0 ]; then
            RESIZE_ARG=" -vf \""
            IN_VF=1
         else
            RESIZE_ARG=","
         fi
      fi

      if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" ${SCALE_WIDTH}x"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then RESIZE_ARG+="scale=${SCALE_WIDTH}:-1"; fi
      elif [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" x${SCALE_HEIGHT}"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then RESIZE_ARG+="scale=-1:${SCALE_HEIGHT}"; fi
      elif [ $SCALE_TYPE -eq $SCALE_WIDTH_HEIGHT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" ${SCALE_WIDTH}x${SCALE_HEIGHT}\\!"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then RESIZE_ARG+="scale=${SCALE_WIDTH}:${SCALE_HEIGHT}"; fi
      elif [ $SCALE_TYPE -eq $SCALE_PERCENT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" ${SCALE_PERC}%"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then
            SAFE_MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_PERC '{printf "%f",w*(p/100)}')
            SAFE_MEDIA_HEIGHT=$(echo | awk -v h=$MEDIA_HEIGHT -v p=$SCALE_PERC '{printf "%f",h*(p/100)}')
         fi
      elif [ $SCALE_TYPE -eq $SCALE_MULTIPLY ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" $((100*$SCALE_MULT))%"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then
            SAFE_MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_MULT '{printf "%f",w*p}')
            SAFE_MEDIA_HEIGHT=$(echo | awk -v h=$MEDIA_HEIGHT -v p=$SCALE_MULT '{printf "%f",h*p}')
         fi
      elif [ $SCALE_TYPE -eq $SCALE_DIVIDE ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then RESIZE_ARG+=" $((100/$SCALE_DIV))%"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then
            SAFE_MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_DIV '{printf "%f",w/p}')
            SAFE_MEDIA_HEIGHT=$(echo | awk -v h=$MEDIA_HEIGHT -v p=$SCALE_DIV '{printf "%f",h/p}')
         fi
      fi
      
      # Make sure numbers we're using are even integers if scaling a movie
      if [ $SCALE_TYPE -eq $SCALE_PERCENT ] || [ $SCALE_TYPE -eq $SCALE_MULTIPLY ] || [ $SCALE_TYPE -eq $SCALE_DIVIDE ]; then
         if [ $SRC_FILE_TYPE == "movie" ]; then
            SAFE_MEDIA_WIDTH=$(round $SAFE_MEDIA_WIDTH)
            if [ $((SAFE_MEDIA_WIDTH % 2)) == 1 ]; then
               let SAFE_MEDIA_WIDTH+=1
            fi
            SAFE_MEDIA_HEIGHT=$(round $SAFE_MEDIA_HEIGHT)
            if [ $((SAFE_MEDIA_HEIGHT % 2)) == 1 ]; then
               let SAFE_MEDIA_HEIGHT+=1
            fi
            RESIZE_ARG+="scale=${SAFE_MEDIA_WIDTH}:${SAFE_MEDIA_HEIGHT}"
         fi
      fi
   fi
   
   # Construct flip operation if requested
   if [ $OPER_FLIP -eq 1 ]; then
      if [ $SRC_FILE_TYPE == "movie" ]; then
         if [ $IN_VF -eq 0 ]; then
            FLIP_ARG=" -vf \""
            IN_VF=1
         else
            FLIP_ARG=","
         fi
      fi

      if [ $FLIP_TYPE -eq $FLIP_HORI ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then FLIP_ARG+=" -flop"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then FLIP_ARG+="hflip"; fi
      elif [ $FLIP_TYPE -eq $FLIP_VERT ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then FLIP_ARG+=" -flip"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then FLIP_ARG+="vflip"; fi
      elif [ $FLIP_TYPE -eq $FLIP_BOTH ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then FLIP_ARG+=" -flip -flop"; fi
         if [ $SRC_FILE_TYPE == "movie" ]; then FLIP_ARG+="vflip,hflip"; fi
      fi
   fi
   
   # Construct rotation operation if requested; the repage command is needed to avoid an error with rotation
   # of TIFFs
   if [ $OPER_ROTATE -eq 1 ]; then
      if [ $SRC_FILE_TYPE == "movie" ]; then
         if [ $IN_VF -eq 0 ]; then
            ROTATE_ARG=" -vf \""
            IN_VF=1
         else
            ROTATE_ARG=","
         fi
      fi

      if [ $SRC_FILE_TYPE == "image" ]; then ROTATE_ARG=" -rotate $ROTATE_DEG +repage"; fi
      if [ $SRC_FILE_TYPE == "movie" ]; then ROTATE_ARG+="rotate=$ROTATE_DEG*(PI/180)"; fi
   fi

   # Construct trim operation if requested (movies only)
   if [ $OPER_TRIM -eq 1 ]; then
      if [ ! -z "$TRIM_FROM" ]; then
         TRIM_ARG_START="-ss $TRIM_FROM"
      fi
      if [ ! -z "$TRIM_TO" ]; then
         TRIM_ARG_END="-to $TRIM_TO"
      fi
   fi

   # Construct speed-change operation if requested (movies only)
   if [ $OPER_SPEED -eq 1 ]; then
      if [ $SPEED_TYPE -eq $SPEED_DOWN ]; then
         # Calculate audio tempo value (1/SPEED_DIV)
         AUDIO_TEMPO=$(echo | awk -v sd=$SPEED_DIV '{printf "%.6f", 1/sd}')
      
         SPEED_ARG=" -filter:v setpts=PTS*$SPEED_DIV -filter:a atempo=$AUDIO_TEMPO"
      elif [ $SPEED_TYPE -eq $SPEED_UP ]; then
         SPEED_ARG=" -filter:v setpts=PTS/$SPEED_MULT -filter:a atempo=$SPEED_MULT"
      fi
   fi

   # Handle beside mode: rename original file before building the command
   INPUT_FILE_REF="$FILE_REF"
   ALTERED_FILE_REF="$FILE_REF"
   NEW_FILE_NAME=$(basename $FILE_REF)
   if [ $FILE_MODE -eq $FILE_BESIDE ]; then
      ORIG_FILE_REF=$(trim "$FILE_REF" before last .$FILE_SUFFIX)
      ORIG_FILE_REF+="-old.$FILE_SUFFIX"
      if [ $DRY_RUN -eq 0 ]; then
         mv "$FILE_REF" "$ORIG_FILE_REF"
      else
         echo mv "$FILE_REF" "$ORIG_FILE_REF"
      fi
      # Use the renamed file as input
      INPUT_FILE_REF="$ORIG_FILE_REF"
   fi

   # Assemble full call to ImageMagick or FFmpeg
   BIN_TOOL=""
   if [ $SRC_FILE_TYPE == "image" ]; then BIN_TOOL="$BIN_CONVERT"; fi
   if [ $SRC_FILE_TYPE == "movie" ]; then BIN_TOOL="$BIN_FFMPEG"; fi
   TOOL_COMMAND="$BIN_TOOL"
   if [ $SRC_FILE_TYPE == "movie" ]; then TOOL_COMMAND+=" -hide_banner -loglevel error -stats $TRIM_ARG_START $TRIM_ARG_END -i"; fi
   TOOL_COMMAND+=" \"$INPUT_FILE_REF\"${CROP_ARG}${RESIZE_ARG}${FLIP_ARG}${ROTATE_ARG}"
   if [ $SRC_FILE_TYPE == "movie" ] && [ $IN_VF -eq 1 ]; then TOOL_COMMAND+="\""; fi # close -vf argument's quotes
   TOOL_COMMAND+="$SPEED_ARG" # contains audio filter so we add the whole command after closing the -vf argument
   
   # Handle mirrored mode: set up output in mirrored directory
   if [ $FILE_MODE -eq $FILE_MIRROR ]; then
      # Create path in new dir. equivalent to path in orig. dir.
      MIRR_PATH=$(trim "$FILE_REF" after first "$SOURCE_DIR/")
      MIRR_PATH=$(dirname "$MIRR_PATH")

      if [ $DRY_RUN -eq 0 ]; then
         if [ ! -d "$DEST_DIR/$MIRR_PATH" ]; then
            mkdir -p "$DEST_DIR/$MIRR_PATH"
         fi
      else
         echo mkdir -p "$DEST_DIR/$MIRR_PATH"
      fi

      # Prepare new file name if conversion was requested
      if [ $OPER_CONVERT -eq 1 ]; then
         CURR_SUFF=$(trim "$FILE_REF" after last .)
         NEW_FILE_NAME=$(trim "$NEW_FILE_NAME" before last .$CURR_SUFF)
         NEW_FILE_NAME+=".$NEW_SUFF"
      fi

      if [ "$MIRR_PATH" == "." ]; then
         MIRR_PATH=""
      else
         MIRR_PATH+="/"
      fi

      ALTERED_FILE_REF="$DEST_DIR/${MIRR_PATH}$NEW_FILE_NAME"
   fi

   # Tell FFmpeg to use the first frame of the video when converting to image
   if [ "$SRC_FILE_TYPE" == "movie" ] && [ "$DST_FILE_TYPE" == "image" ]; then
      TOOL_COMMAND+=" -frames:v 1"
   fi

   # If converting to an audio format, add -q:a 0 to ensure high-quality audio output
   if [ $OPER_CONVERT -eq 1 ] && [ $SRC_FILE_TYPE == "movie" ]; then
      shopt -s nocasematch
      CONV_TO_AUDIO=0
      for SUFFIX in "${AUD_SUFF[@]}"; do
         if [[ "$SUFFIX" == $NEW_SUFF ]]; then
            CONV_TO_AUDIO=1
            break
         fi
      done
      shopt -u nocasematch
      if [ $CONV_TO_AUDIO -eq 1 ]; then
         TOOL_COMMAND+=" -q:a 0"
      fi
   fi

   TOOL_COMMAND+=" \"$ALTERED_FILE_REF\""

   # Assemble statement about operations to be performed
   declare -a OPERATION_NAMES=()
   if [ $OPER_CROP -eq 1 ]; then
      OPERATION_NAMES+=("crop")
   fi
   if [ $OPER_FLIP -eq 1 ]; then
      OPERATION_NAMES+=("flip")
   fi
   if [ $OPER_ROTATE -eq 1 ]; then
      OPERATION_NAMES+=("rotation")
   fi
   if [ $OPER_SCALE -eq 1 ]; then
      OPERATION_NAMES+=("scale")
   fi
   if [ $OPER_CONVERT -eq 1 ]; then
      OPERATION_NAMES+=("conversion")
   fi
   if [ $OPER_TRIM -eq 1 ]; then
      OPERATION_NAMES+=("trim")
   fi
   if [ $OPER_SPEED -eq 1 ]; then
      OPERATION_NAMES+=("speed change")
   fi
   if [ $OPER_LABEL -eq 1 ]; then
      OPERATION_NAMES+=("labeling")
   fi
   OPERATION_STMT="Performing "
   NUM_OPS=${#OPERATION_NAMES[@]}
   if [ $NUM_OPS -gt 1 ]; then
      for ((i = 0; i < $NUM_OPS; ++i)); do
         if [ $i -lt $((NUM_OPS - 2)) ]; then
            OPERATION_STMT+="${OPERATION_NAMES[$i]}, "
         elif [ $i -lt $((NUM_OPS - 1)) ]; then
            OPERATION_STMT+="${OPERATION_NAMES[$i]} and "
         else
            OPERATION_STMT+="${OPERATION_NAMES[$i]}"
         fi
      done
   else
      OPERATION_STMT+="${OPERATION_NAMES[0]}"
   fi

   # Run ImageMagick/FFmpeg command or else print command to terminal if in dry-run mode
   if [ $CHANGE_TYPE -eq $CHANGE_MODIFY ]; then
      if [ $DRY_RUN -eq 0 ]; then
         mypr "$OPERATION_STMT on $(basename $FILE_REF)..."
         eval $TOOL_COMMAND
         TOOL_RESULT=$?

         # Don't keep going if we ran into a tool error
         if [ $TOOL_RESULT -ne 0 ]; then
            mypr "Exiting due to error $TOOL_RESULT when calling $BIN_TOOL."
            exit 99
         fi
      else
         mypr "Would have run command:"
         mypr $TOOL_COMMAND
      fi
   fi

   # Label file with dimensions if requested
   if [ $OPER_LABEL -eq 1 ]; then
      # If we didn't alter the file, it's still back at $FILE_REF or $ORIG_FILE_REF
      if [ $CHANGE_TYPE -eq $CHANGE_LABEL_ONLY ]; then
         if [ $FILE_MODE -eq $FILE_BESIDE ]; then
            ALTERED_FILE_REF="$ORIG_FILE_REF"
         else
            ALTERED_FILE_REF="$FILE_REF"
         fi
         mypr "Labeling $(basename $FILE_REF)..."
      fi

      # Get info on the file we created
      if [ $DRY_RUN -eq 0 ]; then
         if [ $SRC_FILE_TYPE == "image" ]; then
            MEDIA_WIDTH=$("$BIN_IDENTIFY" -format "%[fx:w]" "$ALTERED_FILE_REF")
            MEDIA_HEIGHT=$("$BIN_IDENTIFY" -format "%[fx:h]" "$ALTERED_FILE_REF")
         elif [ $SRC_FILE_TYPE == "movie" ]; then
            MEDIA_DIMS=$("$BIN_FFPROBE" -v quiet -print_format csv=p=0 -show_entries stream=width,height "$ALTERED_FILE_REF")
            MEDIA_WIDTH=$(trim "$MEDIA_DIMS" before first ",")
            MEDIA_HEIGHT=$(trim "$MEDIA_DIMS" after first ",")
         fi
      else # we have to estimate the final size since the altered files won't exist
         if [ $OPER_CROP -eq 1 ]; then
            if [ $CROP_TYPE == $CROP_WIDTH_ONLY ] || [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
               MEDIA_WIDTH=$CROP_WIDTH
            fi

            if [ $CROP_TYPE == $CROP_HEIGHT_ONLY ] || [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
               MEDIA_HEIGHT=$CROP_HEIGHT
            fi
         fi
         if [ $OPER_SCALE -eq 1 ]; then
            if [ $SCALE_TYPE == $SCALE_WIDTH_ONLY ]; then
               let MEDIA_HEIGHT/=$(($MEDIA_WIDTH / $SCALE_WIDTH))
               MEDIA_WIDTH=$SCALE_WIDTH
            elif [ $SCALE_TYPE == $SCALE_HEIGHT_ONLY ]; then
               let MEDIA_WIDTH/=$(($MEDIA_HEIGHT / $SCALE_HEIGHT))
               MEDIA_HEIGHT=$SCALE_HEIGHT
            elif [ $SCALE_TYPE == $SCALE_WIDTH_HEIGHT ]; then
               MEDIA_WIDTH=$SCALE_HEIGHT
               MEDIA_HEIGHT=$SCALE_HEIGHT
            elif [ $SCALE_TYPE == $SCALE_PERCENT ]; then
               MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_PERC '{printf "%f",w*(p/100)}')
               MEDIA_WIDTH=$(round $MEDIA_WIDTH)
               if [ $SRC_FILE_TYPE == "movie" ] && [ $((MEDIA_WIDTH % 2)) == 1 ]; then
                  let MEDIA_WIDTH+=1
               fi
               MEDIA_HEIGHT=$(echo | awk -v h=$MEDIA_HEIGHT -v p=$SCALE_PERC '{printf "%f",h*(p/100)}')
               MEDIA_HEIGHT=$(round $MEDIA_HEIGHT)
               if [ $SRC_FILE_TYPE == "movie" ] && [ $((MEDIA_HEIGHT % 2)) == 1 ]; then
                  let MEDIA_HEIGHT+=1
               fi
            elif [ $SCALE_TYPE -eq $SCALE_MULTIPLY ]; then
               MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_MULT '{printf "%f",w*p}')
               MEDIA_WIDTH=$(round $MEDIA_WIDTH)
               if [ $SRC_FILE_TYPE == "movie" ] && [ $((MEDIA_WIDTH % 2)) == 1 ]; then
                  let MEDIA_WIDTH+=1
               fi
            else # SCALE_DIVIDE
               MEDIA_WIDTH=$(echo | awk -v w=$MEDIA_WIDTH -v p=$SCALE_DIV '{printf "%f",w/p}')
               MEDIA_WIDTH=$(round $MEDIA_WIDTH)
               if [ $SRC_FILE_TYPE == "movie" ] && [ $((MEDIA_WIDTH % 2)) == 1 ]; then
                  let MEDIA_WIDTH+=1
               fi
            fi
         fi
      fi

      # Prepare new name
      CURR_SUFF=$(trim "$ALTERED_FILE_REF" after last .)
      LABELED_FILE_NAME=$(trim "$NEW_FILE_NAME" before last .$CURR_SUFF)
      LABELED_FILE_NAME+=" ${MEDIA_WIDTH}x${MEDIA_HEIGHT}.$CURR_SUFF"

      # If we actually changed the file, move the file to its new name with label
      if [ $CHANGE_TYPE -eq $CHANGE_MODIFY ]; then
         if [ $DRY_RUN -eq 0 ]; then
            mv "$ALTERED_FILE_REF" "$(dirname $ALTERED_FILE_REF)/$LABELED_FILE_NAME"
         else
            echo mv "$ALTERED_FILE_REF" "$(dirname $ALTERED_FILE_REF)/$LABELED_FILE_NAME"
         fi
      # If all we're doing is labeling the files then the tool never ran, so just 'cp' or 'mv' the original
      # file depending on the file mode
      elif [ $CHANGE_TYPE -eq $CHANGE_LABEL_ONLY ]; then
         if [ $DRY_RUN -eq 0 ]; then
            if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
               mv "$FILE_REF" "$(dirname $FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
               cp "$ORIG_FILE_REF" "$(dirname $ORIG_FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
               cp "$FILE_REF" "$DEST_DIR/${MIRR_PATH}$LABELED_FILE_NAME"
            fi
         else
            if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
               echo mv "$FILE_REF" "$(dirname $FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
               echo cp "$ORIG_FILE_REF" "$(dirname $ORIG_FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
               echo cp "$FILE_REF" "$DEST_DIR/${MIRR_PATH}$LABELED_FILE_NAME"
            fi
         fi
      fi
   fi
done
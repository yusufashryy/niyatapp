# Generates Salah.xcodeproj from project.yml. Needs XcodeGen: `brew install xcodegen`.

.PHONY: project full open verses clean

# Free Apple ID: everything except Prayer Lock.
project:
	SALAH_FULL=false xcodegen generate

# Paid Apple Developer account: adds Prayer Lock (Screen Time) and Time Sensitive alerts.
full:
	SALAH_FULL=true xcodegen generate

open:
	open Salah.xcodeproj

verses:
	python3 scripts/generate_daily_verses.py

clean:
	rm -rf Salah.xcodeproj build DerivedData

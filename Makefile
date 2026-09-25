# Generates Niyati.xcodeproj from project.yml. Needs XcodeGen: `brew install xcodegen`.

.PHONY: project full open verses clean

# Free Apple ID: everything except Prayer Lock.
project:
	NIYATI_FULL=false xcodegen generate

# Paid Apple Developer account: adds Prayer Lock (Screen Time) and Time Sensitive alerts.
full:
	NIYATI_FULL=true xcodegen generate

open:
	open Niyati.xcodeproj

verses:
	python3 scripts/generate_daily_verses.py

clean:
	rm -rf Niyati.xcodeproj build DerivedData

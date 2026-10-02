# Generates Niyat.xcodeproj from project.yml. Needs XcodeGen: `brew install xcodegen`.

.PHONY: setup project full open update verses clean model

# First time: finds your team ID, writes Config/Local.xcconfig, opens Xcode.
setup:
	./scripts/setup.sh

# Get the latest changes and rebuild the project.
update:
	git pull
	$(MAKE) project

# Free Apple ID: everything except Prayer Lock.
project: model
	NIYAT_FULL=false xcodegen generate

# Paid Apple Developer account: adds Prayer Lock (Screen Time) and Time Sensitive alerts.
full: model
	NIYAT_FULL=true xcodegen generate

# The built-in recitation model (166 MB, not in git): downloaded once.
model:
	./scripts/fetch_recitation_model.sh

open:
	open Niyat.xcodeproj

verses:
	python3 scripts/generate_daily_verses.py

clean:
	rm -rf Niyat.xcodeproj build DerivedData

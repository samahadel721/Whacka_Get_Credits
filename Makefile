# اختصارات — Termux: pkg install -y make
SHELL := /usr/bin/env bash
HERE  := $(CURDIR)
NAME ?= demo
T    ?= node-api

.PHONY: help setup doctor new serve backup tunnel check test lint clean

help:            ## عرض الأوامر المتاحة
	@grep -hE '^[a-z-]+:.*?##' $(MAKEFILE_LIST) | awk -F'##' '{printf "  %-10s %s\n", $$1, $$2}'

setup:           ## تجهيز البيئة على Termux
	@bash $(HERE)/scripts/setup.sh -y

doctor:          ## فحص صحة البيئة
	@bash $(HERE)/scripts/doctor.sh

new:             ## مشروع جديد: make new NAME=app T=node-api
	@bash $(HERE)/scripts/project.sh $(NAME) --template $(T)

DIR ?= .
serve:           ## سيرفر تطوير: make serve DIR=~/projects/app [PORT=8080]
	@bash $(HERE)/scripts/serve.sh $(DIR) $(if $(PORT),--port $(PORT),)

backup:          ## نسخة احتياطية + push
	@bash $(HERE)/scripts/backup.sh --push

stop:            ## إيقاف سيرفر يسمع على بورت: make stop PORT=8080
	@bash $(HERE)/scripts/serve.sh --stop $(if $(PORT),--port $(PORT),)

status:          ## من يسمع على البورت؟ make status PORT=8080
	@bash $(HERE)/scripts/serve.sh --status $(if $(PORT),--port $(PORT),)

tunnel:          ## نفق تجريبي: make tunnel PORT=8080
	@bash $(HERE)/scripts/tunnel.sh $(PORT)

check:           ## فحص صيغة كل سكربتات shell والـ JS
	@fail=0; \
	for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$$f" || fail=1; done; \
	for f in $(shell find templates -name '*.js' 2>/dev/null); do node --check "$$f" >/dev/null || fail=1; done; \
	for f in $(shell find templates -name '*.py' 2>/dev/null); do python3 -c "import sys;compile(open(sys.argv[1],encoding='utf-8').read(),sys.argv[1],'exec')" "$$f" || fail=1; done; \
	[ $$fail -eq 0 ] && echo "✓ كل الملفات صالحة" || (echo "✗ في أخطاء صيغة"; exit 1)

test:            ## اختبار القوالب (تشغّل الخوادم فعليًا)
	@bash tests/run.sh

lint:            ## shellcheck إن كان مثبتًا
	@command -v shellcheck >/dev/null 2>&1 \
	  && shellcheck -x scripts/*.sh scripts/lib/*.sh \
	  || echo "shellcheck غير مثبّت — pkg install -y shellcheck"

clean:           ## حذف ملفات الاختبار المؤقتة
	@rm -rf .tmp-tests templates/*/__pycache__ && echo "✓ نظيف"

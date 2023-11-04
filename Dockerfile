# required on all stages..e.g. CAs and timezones should never be stale
ARG SYS_PACKAGES="ca-certificates tzdata"
# Any extra packages to install can go here
ARG EXTRA_SYS_PACKAGES="\
  librdkafka-dev \
  libpq5 \
  "
ARG POETRY_VERSION=1.5.1
ARG PROJECT_NAME=deployment
ARG PY_ROOT_MODULE=app
ARG PY_VER_FULL=3.10.12
ARG PY_VER_MAJOR=3.10

FROM python:${PY_VER_FULL} as base
ARG SYS_PACKAGES
ARG EXTRA_SYS_PACKAGES
ARG PROJECT_NAME
ARG PY_VER_MAJOR
ARG POETRY_VERSION

ENV PROJECT_HOME=/opt/${PROJECT_NAME}
ENV PROJECT_PYTHONPATH=${PROJECT_HOME}/.venv/lib/python${PY_VER_MAJOR}/site-packages
ENV PROJECT_VENV_BIN=${PROJECT_HOME}/.venv/bin
ENV PATH=${PROJECT_VENV_BIN}${PATH:+":$PATH"}

RUN pip install poetry==${POETRY_VERSION}

RUN apt-get update --no-install-recommends \
  && apt-get install --no-install-recommends --yes \
  ${SYS_PACKAGES} \
  ${EXTRA_SYS_PACKAGES} \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove \
  && apt-get clean \
  && mkdir --parents ${PROJECT_VENV_BIN}  # also creates PROJECT_HOME

WORKDIR ${PROJECT_HOME}

# ================================================================
# Builder image
# ================================================================
FROM base as builder
ARG PY_ROOT_MODULE
ARG ARTIFACTORY_PYPI_USERNAME
ARG ARTIFACTORY_PYPI_PASSWORD

ENV POETRY_HTTP_BASIC_SHIPT_RESOLVE_USERNAME=$ARTIFACTORY_PYPI_USERNAME
ENV POETRY_HTTP_BASIC_SHIPT_RESOLVE_PASSWORD=$ARTIFACTORY_PYPI_PASSWORD

# separate caching layer for deps
COPY pyproject.toml poetry.lock ./
RUN poetry install --only=main --no-root

# caching layer for root
COPY ${PY_ROOT_MODULE} ${PY_ROOT_MODULE}/

# # ================================================================
# # Dev Image
# # ================================================================
# FROM builder as dev

# ARG PY_ROOT_MODULE

# ENV PROMETHEUS_MULTIPROC_DIR=/tmp

# RUN poetry install

# COPY .tool-versions Makefile ./
# COPY tests tests/

# ================================================================
# Prod Image
# only module and venv related files
# ================================================================
FROM python:${PY_VER_FULL}-slim as prod
ARG SYS_PACKAGES
ARG EXTRA_SYS_PACKAGES
ARG PROJECT_NAME
ARG PY_ROOT_MODULE
ARG PY_VER_MAJOR

###### START same as base - TODO way to DRY this out?
ENV PROJECT_HOME=/opt/${PROJECT_NAME}
ENV PROJECT_PYTHONPATH=${PROJECT_HOME}/.venv/lib/python${PY_VER_MAJOR}/site-packages
ENV PROJECT_VENV_BIN=${PROJECT_HOME}/.venv/bin
# prefix the venv bin to the path
ENV PATH=${PROJECT_VENV_BIN}${PATH:+":$PATH"}

RUN apt-get update --no-install-recommends \
  && apt-get install --no-install-recommends --yes \
  ${SYS_PACKAGES} \
  ${EXTRA_SYS_PACKAGES} \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove \
  && apt-get clean \
  && mkdir --parents ${PROJECT_VENV_BIN}

WORKDIR ${PROJECT_HOME}

###### END same as base

# Copy over pyproject.toml - used to retrieve app name / version
COPY --from=builder ${PROJECT_HOME}/pyproject.toml ${PROJECT_HOME}/pyproject.toml

COPY --from=builder ${PROJECT_PYTHONPATH} ${PROJECT_PYTHONPATH}
COPY --from=builder ${PROJECT_VENV_BIN} ${PROJECT_VENV_BIN}/
COPY --from=builder "${PROJECT_HOME}/${PY_ROOT_MODULE}" ${PY_ROOT_MODULE}/

ENV PYTHONPATH=${PROJECT_PYTHONPATH}${PYTHONPATH:+":$PYTHONPATH"}

ENV USERNAME=metaflow_user

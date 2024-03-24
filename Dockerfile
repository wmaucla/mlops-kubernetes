ARG PROJECT_NAME=deployment
ARG PY_VER_FULL=3.10.12
ARG PY_VER_MAJOR=3.10

FROM python:${PY_VER_FULL} as base
ARG SYS_PACKAGES
ARG EXTRA_SYS_PACKAGES
ARG PROJECT_NAME
ARG PY_VER_MAJOR

ENV PROJECT_HOME=/opt/${PROJECT_NAME}
ENV PROJECT_PYTHONPATH=${PROJECT_HOME}/.venv/lib/python${PY_VER_MAJOR}/site-packages
ENV PROJECT_VENV_BIN=${PROJECT_HOME}/.venv/bin
ENV PATH=${PROJECT_VENV_BIN}${PATH:+":$PATH"}

RUN pip install poetry==1.5.1

RUN apt-get update --no-install-recommends \
  && apt-get install --no-install-recommends --yes \
  && apt-get autoremove \
  && apt-get clean \
  && mkdir --parents ${PROJECT_VENV_BIN}

WORKDIR ${PROJECT_HOME}

FROM base as builder
ARG ARTIFACTORY_PYPI_USERNAME
ARG ARTIFACTORY_PYPI_PASSWORD

ENV POETRY_HTTP_BASIC_SHIPT_RESOLVE_USERNAME=$ARTIFACTORY_PYPI_USERNAME
ENV POETRY_HTTP_BASIC_SHIPT_RESOLVE_PASSWORD=$ARTIFACTORY_PYPI_PASSWORD

COPY pyproject.toml poetry.lock ./
RUN poetry install --only=main --no-root

COPY app app/

FROM python:${PY_VER_FULL}-slim as prod
ARG SYS_PACKAGES
ARG PROJECT_NAME
ARG PY_VER_MAJOR

ENV PROJECT_HOME=/opt/${PROJECT_NAME}
ENV PROJECT_PYTHONPATH=${PROJECT_HOME}/.venv/lib/python${PY_VER_MAJOR}/site-packages
ENV PROJECT_VENV_BIN=${PROJECT_HOME}/.venv/bin
ENV PATH=${PROJECT_VENV_BIN}${PATH:+":$PATH"}

RUN apt-get update --no-install-recommends \
  && apt-get install --no-install-recommends --yes \
  ${SYS_PACKAGES} \
  && apt-get autoremove \
  && apt-get clean \
  && mkdir --parents ${PROJECT_VENV_BIN}

WORKDIR ${PROJECT_HOME}

COPY --from=builder ${PROJECT_PYTHONPATH} ${PROJECT_PYTHONPATH}
COPY --from=builder ${PROJECT_VENV_BIN} ${PROJECT_VENV_BIN}/
COPY --from=builder "${PROJECT_HOME}/app" app/

ENV PYTHONPATH=${PROJECT_PYTHONPATH}${PYTHONPATH:+":$PYTHONPATH"}

ENV USERNAME=metaflow_user

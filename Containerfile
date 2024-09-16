FROM docker.io/squidfunk/mkdocs-material:9

COPY requirements.txt requirements.txt

RUN pip install -r requirements.txt

ENTRYPOINT [ "mkdocs" ]

EXPOSE 8000/TCP

CMD [ "serve", "--dev-addr=0.0.0.0:8000" ]

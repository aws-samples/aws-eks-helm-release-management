FROM public.ecr.aws/p8v8e7e5/myartifacts:alpine-3.8
RUN apk add python3
RUN apk add py3-pip 
RUN python3 -m ensurepip &&\
pip3 install --upgrade pip
RUN pip3 install flask



ENV FLASK_APP app.py
ENV PLATFORM 'Amazon EKS'

WORKDIR /app
COPY . /app/


CMD ["python3", "app.py"]

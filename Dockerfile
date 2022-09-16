FROM nginx:1.16.0
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN echo "Asia/Shanghai" > /etc/timezone

COPY  ./dist /frontend/

COPY ./nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
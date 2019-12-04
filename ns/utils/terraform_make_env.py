import base64
import json
import os
import sys


def main():
    terraform_output = json.load(sys.stdin)
    namespace = os.getenv('CLUSTER_NAMESPACE')
    print('export STATE_REPO={val}'.format(val=terraform_output['state_{ns}_repo'.format(ns=namespace)]['value']))


if __name__ == '__main__':
    main()

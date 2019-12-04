import base64
import json
import sys


def main():
    terraform_output = json.load(sys.stdin)
    print('export CLUSTER_NAME={value}'.format(value=terraform_output['cluster_name']['value']))
    print('export INFRA_REPO={value}'.format(value=terraform_output['infra_repo']['value']))
    print('export STATE_REPO={value}'.format(value=terraform_output['state_repo']['value']))


if __name__ == '__main__':
    main()

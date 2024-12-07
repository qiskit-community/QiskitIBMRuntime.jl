# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

circ_str1 = "eJyl1wVQlGkcx/F91wDF7lbswsZWMFCxBezEFRXFYAU7xuvu7u7uPq+7S6+7uz3v5o4f+13kd3PMnXM7w3z4qssL+jz//zgtM3tCZk5SUCkIxV5BXmEoaWkoseTTHSUfYX45XO7z6pH8aKQ4vyild+rA9PCerTv6Ju/esq0wKH1LEBSG/BWU+xJ6VcLKWAWrYgImYrX4YzEJa2BNrIW1sQ7WxXpYHxtgQ2yEjbEJNsVm2BxbYEtsha2xDSZjW2yH7bEDdsRO2Bm7YFfsht0xBXtgT+yFvbEP9sV+mIr9cQAOxEE4GIfgUByGwzEN03EEjsRROBozcAyOxXGYieNxAk7ESTgZp+BUnIZZmI05OB1n4EychbNxDs7FeTgfF+BCXIS5uBgjuATzcCkuw+WYjytwJRbgKlyNa3Atxu9jFNdhERbjetyAG3ETbsYtuBW34faIbno4VDlYlZcbf0j8FZR9VpUKQv/8ypozNrcor/Sbjv+NJDZJGZ2zL3lvWtmMqOjN2bPK3nwADwr+9qBquw7gQcH/e1B82oUreHPGqKyyHyn2uPi8rOhx5f4K/u2Lj8yNRvPzouW+ePwdFf08k0r+aYujsS8fsWf8h3cEkdifiW2Kko8/S158e+HC2OnZvz/K9kXp72wLJQS5qyP5BQXx+7QTD8KD8RA8FA/Dw/EIPBKPwqPxGDwWj8Pj8QQ8EU/Ck/EUPBVPw9PxDDwTz8Kz8Rw8F8/D8/ECvBAvwovxErwUL8PL8Qq8Eq/Cq/EavBavw+vxBrwRb8Kb8Ra8FW/D2/EOvBPvwrvxHrwX78P7cRc+gA/iQ/gwPoKP4mP4OD6BT+JT+DQ+g8/ic/g8voAv4kv4Mr6Cr+JruBv34Ov4Br6Jb+Hb+A6+i+/h+/gBfogf4cf4CX6Kn+Hn+AV+iV/h1/gNfovf4ff4A/6IP+HP+Av+invxN9yHv+MfGMQmE5/olbB/EASeYc9KnpU9q3hW9UzwTPSs5lndM8mzhmdNz1qetT3reNb1rOdZ37OBZ0PPRp6NPZt4NvVs5tncs4VnS89Wnq0923gme7b1bOfZ3rODZ0fPTp6dPbt4dvXs5tndM8Wzh2dPz16evT37ePb17OeZ6tnfc4DnQM9BnoM9h3gO9RzmOdwzzTPdc4TnSM9RnqM9MzzHeI71HOeZ6Tnec4LnRM9JnpM9p3hO9ZzmmeWZ7ZnjOd1zhudMz1mesz3neM71nOc533OB50LPRZ65nos9I55LPPM8l3ou81zume+5wnOlZ4HnKs/Vnms813oWekY913kWeRZ7rvfc4LnRc5PnZs8tnls99QpCseWpjak1qd1YuhBDsdWnfaclp82mdaYdpsWlbaUVpb2kZaQNpLWjXaMFo62iVaL9oaWhTaH1oJ2gRaDp3yYUm/Ma7proGuOa3RrYmtIazZrHGsKavBq3mrEarJqmGqGamxqWmpAai5qFGoCaehp1mm8aappkGl+aWRpUmk7podgc0vDRxNGY0WzRQNEU0ejQvNCQ0GTQONAM0MXXbdcV173WZdYN1rXVXdUF1a3UVdT906XTTdP10p3SRdLtWRSK3RNdDt0IXQOdfR14nXIdbZ1nHWKdXB1XnVEdTJ1GHUGdOx02nTAdK50lHSCdGh0VnQ8dCp0E/fPrP+3b/wJnvGDM"


payload1 =
"""
{
    "program_id": "sampler",
    "hub": "hub-one",
    "group": "group-one",
    "params": {
        "support_qiskit": true,
        "pubs": [
            [
                {
                    "__value__": "eJyl1wVQlGkcx/F91wDF7lbswsZWMFCxBezEFRXFYAU7xuvu7u7uPq+7S6+7uz3v5o4f+13kd3PMnXM7w3z4qssL+jz//zgtM3tCZk5SUCkIxV5BXmEoaWkoseTTHSUfYX45XO7z6pH8aKQ4vyild+rA9PCerTv6Ju/esq0wKH1LEBSG/BWU+xJ6VcLKWAWrYgImYrX4YzEJa2BNrIW1sQ7WxXpYHxtgQ2yEjbEJNsVm2BxbYEtsha2xDSZjW2yH7bEDdsRO2Bm7YFfsht0xBXtgT+yFvbEP9sV+mIr9cQAOxEE4GIfgUByGwzEN03EEjsRROBozcAyOxXGYieNxAk7ESTgZp+BUnIZZmI05OB1n4EychbNxDs7FeTgfF+BCXIS5uBgjuATzcCkuw+WYjytwJRbgKlyNa3Atxu9jFNdhERbjetyAG3ETbsYtuBW34faIbno4VDlYlZcbf0j8FZR9VpUKQv/8ypozNrcor/Sbjv+NJDZJGZ2zL3lvWtmMqOjN2bPK3nwADwr+9qBquw7gQcH/e1B82oUreHPGqKyyHyn2uPi8rOhx5f4K/u2Lj8yNRvPzouW+ePwdFf08k0r+aYujsS8fsWf8h3cEkdifiW2Kko8/S158e+HC2OnZvz/K9kXp72wLJQS5qyP5BQXx+7QTD8KD8RA8FA/Dw/EIPBKPwqPxGDwWj8Pj8QQ8EU/Ck/EUPBVPw9PxDDwTz8Kz8Rw8F8/D8/ECvBAvwovxErwUL8PL8Qq8Eq/Cq/EavBavw+vxBrwRb8Kb8Ra8FW/D2/EOvBPvwrvxHrwX78P7cRc+gA/iQ/gwPoKP4mP4OD6BT+JT+DQ+g8/ic/g8voAv4kv4Mr6Cr+JruBv34Ov4Br6Jb+Hb+A6+i+/h+/gBfogf4cf4CX6Kn+Hn+AV+iV/h1/gNfovf4ff4A/6IP+HP+Av+invxN9yHv+MfGMQmE5/olbB/EASeYc9KnpU9q3hW9UzwTPSs5lndM8mzhmdNz1qetT3reNb1rOdZ37OBZ0PPRp6NPZt4NvVs5tncs4VnS89Wnq0923gme7b1bOfZ3rODZ0fPTp6dPbt4dvXs5tndM8Wzh2dPz16evT37ePb17OeZ6tnfc4DnQM9BnoM9h3gO9RzmOdwzzTPdc4TnSM9RnqM9MzzHeI71HOeZ6Tnec4LnRM9JnpM9p3hO9ZzmmeWZ7ZnjOd1zhudMz1mesz3neM71nOc533OB50LPRZ65nos9I55LPPM8l3ou81zume+5wnOlZ4HnKs/Vnms813oWekY913kWeRZ7rvfc4LnRc5PnZs8tnls99QpCseWpjak1qd1YuhBDsdWnfaclp82mdaYdpsWlbaUVpb2kZaQNpLWjXaMFo62iVaL9oaWhTaH1oJ2gRaDp3yYUm/Ma7proGuOa3RrYmtIazZrHGsKavBq3mrEarJqmGqGamxqWmpAai5qFGoCaehp1mm8aappkGl+aWRpUmk7podgc0vDRxNGY0WzRQNEU0ejQvNCQ0GTQONAM0MXXbdcV173WZdYN1rXVXdUF1a3UVdT906XTTdP10p3SRdLtWRSK3RNdDt0IXQOdfR14nXIdbZ1nHWKdXB1XnVEdTJ1GHUGdOx02nTAdK50lHSCdGh0VnQ8dCp0E/fPrP+3b/wJnvGDM",
                    "__type__": "QuantumCircuit"
                },
                [
                ]
            ]
        ],
        "version": 2,
        "options": {
            "dynamical_decoupling": {
                "enable": true
            },
            "twirling": {
                "num_randomizations": 1000,
                "enable_gates": true
            }
        }
    },
    "project": "project-one",
    "backend": "ibm_kyiv"
}"""
